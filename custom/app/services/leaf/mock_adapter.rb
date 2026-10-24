class Leaf::MockAdapter
  FIXTURE_PATH = File.expand_path('fixtures/customers.json', __dir__).freeze
  MAX_OPEN_INVOICES = 5
  DISCONNECT_LOG = 'Desconectado pelo atendente'.freeze

  def initialize(account_id:, settings: {})
    @account_id = account_id
    @settings = settings || {}
  end

  def find_customer(identifier:, matched_by:)
    record = locate(identifier, matched_by)
    return if record.blank?

    Leaf::Contract.customer(matched_by: matched_by, customer: presented_customer(record, identifier))
  end

  def match?(identifier:, matched_by:)
    locate(identifier, matched_by).present?
  end

  def invoices(identifier:, matched_by:, contract_number: nil)
    record = locate(identifier, matched_by)
    raise Leaf::Contract::Error, 'not_found' if record.blank?

    contracts = Array(record['contracts'])
    scoped = scoped_contracts(contracts, contract_number)
    ranked = ranked_invoices(scoped)
    Leaf::Contract.invoices(
      contract_number: response_contract_number(contract_number, ranked),
      payment_methods: methods_for(scoped, ranked, contract_number),
      open_invoices: ranked.map { |entry| entry[:invoice] }
    )
  end

  def payment(identifier:, matched_by:, invoice_id:, payment_method:)
    record = locate(identifier, matched_by)
    raise Leaf::Contract::Error, 'not_found' if record.blank?

    contract = contract_for_invoice(record, invoice_id)
    raise Leaf::Contract::Error, 'unknown_invoice' if contract.nil?
    unless Array(contract['payment_methods']).include?(payment_method)
      raise Leaf::Contract::Error, 'unknown_method'
    end

    Leaf::Contract.payment(
      method: payment_method,
      invoice_id: invoice_id,
      details: payment_details(payment_method, invoice_id)
    )
  end

  def unblock(identifier:, matched_by:)
    record = locate(identifier, matched_by)
    raise Leaf::Contract::Error, 'not_found' if record.blank?
    raise Leaf::Contract::Error, 'connection_not_blocked' unless blocked_connection?(record, identifier)

    write_state(identifier, 'unblocked' => true, 'disconnected' => false)
    refreshed = presented_customer(record, identifier)
    Leaf::Contract.unblock(name: refreshed.fetch(:name), connection: refreshed.fetch(:connection))
  end

  def disconnect(identifier:, matched_by:)
    record = locate(identifier, matched_by)
    raise Leaf::Contract::Error, 'not_found' if record.blank?

    write_state(identifier, 'disconnected' => true)
    refreshed = presented_customer(record, identifier)
    Leaf::Contract.disconnect(name: refreshed.fetch(:name), connection: refreshed.fetch(:connection))
  end

  def clear_mac(identifier:, matched_by:)
    record = locate(identifier, matched_by)
    raise Leaf::Contract::Error, 'not_found' if record.blank?

    write_state(identifier, 'mac_cleared' => true)
    Leaf::Contract.clear_mac(name: record.fetch('name'))
  end

  def test_connection
    url = setting('system_url')
    key = setting('api_key')
    raise Leaf::Contract::Error, 'invalid_credentials' unless url.present? && key.present?

    Leaf::Contract.connection_test
  end

  private

  def locate(identifier, matched_by)
    key = identifier_key(matched_by)
    customers.find { |customer| customer[key] == identifier }
  end

  def identifier_key(matched_by)
    return 'cpf_cnpj' if matched_by == 'cpf_cnpj'
    return 'phone_number' if matched_by == 'phone'

    raise ArgumentError, 'invalid leaf matched_by'
  end

  def scoped_contracts(contracts, contract_number)
    return contracts if contract_number.blank?

    contracts.select { |contract| contract['number'] == contract_number }
  end

  def ranked_invoices(contracts)
    entries = contracts.flat_map { |contract| invoice_entries(contract) }
    entries.sort_by { |entry| entry[:due_on] }.first(MAX_OPEN_INVOICES)
  end

  def invoice_entries(contract)
    Array(contract['open_invoices']).map do |invoice|
      {
        due_on: invoice.fetch('due_on'),
        contract_number: contract.fetch('number'),
        payment_methods: Array(contract['payment_methods']),
        invoice: invoice
      }
    end
  end

  def methods_for(contracts, ranked, contract_number)
    if contract_number.present?
      contract = contracts.find { |item| item['number'] == contract_number }
      return Array(contract && contract['payment_methods'])
    end

    lists = ranked.map { |entry| entry[:payment_methods] }
    return [] if lists.empty?

    lists.reduce { |common, methods| common & methods }
  end

  def response_contract_number(requested, ranked)
    return requested if requested.present?

    numbers = ranked.map { |entry| entry[:contract_number] }.uniq
    numbers.first if numbers.one?
  end

  def contract_for_invoice(record, invoice_id)
    Array(record['contracts']).find do |contract|
      Array(contract['open_invoices']).any? { |invoice| invoice['id'] == invoice_id }
    end
  end

  def blocked_connection?(record, identifier)
    presented_customer(record, identifier).fetch(:connection)['blocked'] == true
  end

  def presented_customer(record, identifier)
    customer = {
      name: record.fetch('name'),
      registration_status: record.fetch('registration_status'),
      connection: presented_connection(record, identifier)
    }
    customer[:contracts] = presented_contracts(record['contracts']) if record['contracts'].present?
    customer
  end

  def presented_contracts(contracts)
    contracts.map do |contract|
      {
        'number' => contract.fetch('number'),
        'label' => contract.fetch('label'),
        'payment_methods' => contract.fetch('payment_methods')
      }
    end
  end

  def presented_connection(record, identifier)
    connection = record.fetch('connection').deep_dup
    state = connection_state(identifier)
    apply_unblock!(connection) if state['unblocked']
    apply_disconnect!(connection) if state['disconnected']
    connection
  end

  def apply_unblock!(connection)
    connection['blocked'] = false
    connection['status'] = 'online'
    return unless connection['onu'].is_a?(Hash)

    connection['onu']['status'] = 'online'
    connection['onu'].delete('error')
  end

  def apply_disconnect!(connection)
    connection['status'] = 'offline'
    connection['last_log'] = DISCONNECT_LOG
  end

  def connection_state(identifier)
    state = Rails.cache.read(state_cache_key(identifier))
    state.is_a?(Hash) ? state : {}
  end

  def write_state(identifier, changes)
    Rails.cache.write(state_cache_key(identifier), connection_state(identifier).merge(changes))
  end

  def state_cache_key(identifier)
    ['leaf-admin', 'connection', @account_id, identifier].join(':')
  end

  def setting(key)
    return unless @settings.is_a?(Hash)

    @settings[key] || @settings[key.to_sym]
  end

  def payment_details(payment_method, invoice_id)
    case payment_method
    when 'pix' then pix_details(invoice_id)
    when 'boleto' then { pdf_base64: boleto_pdf_base64 }
    when 'card' then { payment_url: "https://pay.example/#{invoice_id}" }
    else raise Leaf::Contract::Error, 'unknown_method'
    end
  end

  def pix_details(invoice_id)
    {
      copy_paste: pix_copy_paste(invoice_id),
      image_base64: pix_image_base64
    }
  end

  def pix_copy_paste(invoice_id)
    "00020126580014BR.GOV.BCB.PIX0114#{invoice_id}5204000053039865802BR6304LEAF"
  end

  def pix_image_base64
    @pix_image_base64 ||= encoded_fixture('pix.png')
  end

  def boleto_pdf_base64
    @boleto_pdf_base64 ||= encoded_fixture('boleto.pdf')
  end

  def encoded_fixture(filename)
    Base64.strict_encode64(File.binread(File.expand_path("fixtures/#{filename}", __dir__)))
  end

  def customers
    @customers ||= JSON.parse(File.read(FIXTURE_PATH))
  end
end
