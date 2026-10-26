class Leaf::Client
  PAYMENT_TYPES = {
    'pix' => 'pix',
    'boleto' => 'bankSlip',
    'card' => 'creditCard'
  }.freeze
  NO_ALARM = 'ND'

  def self.build(hook)
    new(Leaf::HttpAdapter.new(settings: hook.settings))
  end

  def initialize(adapter)
    @adapter = adapter
  end

  def customer(contact, contract_number: nil)
    contracts, matched_by = contracts_for(contact)
    return Leaf::Contract.missing_identifier if matched_by.nil?
    return Leaf::Contract.not_found if contracts.empty?

    contract = select_contract(contracts, contract_number)
    Leaf::Contract.customer(
      matched_by: matched_by,
      customer: customer_payload(contract, contracts, connection_row(contract))
    )
  end

  def invoices(contact, contract_number:)
    contract = owned_contract(contact, contract_number)
    body = @adapter.delayed_billets(contract['id'])
    Leaf::Contract.invoices(
      contract_number: contract['id'].to_s,
      payment_methods: payment_method_names(body['paymentMethods']),
      open_invoices: invoice_rows(body)
    )
  end

  def payment(contact, contract_number:, invoice_id:, method:)
    contract = owned_contract(contact, contract_number)
    body = @adapter.delayed_billets(contract['id'])
    methods = payment_method_names(body['paymentMethods'])
    raise Leaf::Contract::Error, 'unknown_method' unless methods.include?(method)
    unless Array(body['results']).any? { |row| row['id'].to_s == invoice_id.to_s }
      raise Leaf::Contract::Error, 'unknown_invoice'
    end

    payment_body = @adapter.payment(invoice_id, PAYMENT_TYPES.fetch(method))
    Leaf::Contract.payment(
      method: method,
      invoice_id: invoice_id,
      details: payment_details(method, payment_body)
    )
  end

  def unblock(contact, contract_number:)
    contract = owned_contract(contact, contract_number)
    envelope = @adapter.extend_connection(required_connection_id(contract))
    [
      Leaf::Contract.unblock(name: contract['name'].to_s, connection: connection_payload(contract)),
      envelope['detailDescription']
    ]
  end

  def disconnect(contact, contract_number:)
    contract = owned_contract(contact, contract_number)
    envelope = @adapter.disconnect(required_connection_id(contract))
    [
      Leaf::Contract.disconnect(name: contract['name'].to_s, connection: connection_payload(contract, offline: true)),
      envelope['detailDescription']
    ]
  end

  def clear_mac(contact, contract_number:)
    contract = owned_contract(contact, contract_number)
    envelope = @adapter.clear_mac(required_connection_id(contract))
    [Leaf::Contract.clear_mac(name: contract['name'].to_s), envelope['detailDescription']]
  end

  def test_connection
    @adapter.test_connection
    Leaf::Contract.connection_test
  end

  private

  def contracts_for(contact)
    document = digits(contact.custom_attributes&.[]('cpf_cnpj'))
    phone = digits(contact.phone_number)
    return [nil, nil] if document.nil? && phone.nil?

    if document
      rows = @adapter.list_contracts(document: document)
      return [rows, 'cpf_cnpj'] if rows.any?
    end

    if phone
      rows = @adapter.list_contracts(phone: phone)
      return [rows, 'phone'] if rows.any?
    end

    [[], document ? 'cpf_cnpj' : 'phone']
  end

  def owned_contract(contact, contract_number)
    raise Leaf::Contract::Error, 'not_found' if contract_number.blank?

    contracts, matched_by = contracts_for(contact)
    raise Leaf::Contract::Error, 'missing_identifier' if matched_by.nil?

    found = Array(contracts).find { |item| item['id'].to_s == contract_number.to_s }
    raise Leaf::Contract::Error, 'not_found' unless found

    found
  end

  def select_contract(contracts, contract_number)
    return contracts.first if contract_number.blank?

    found = contracts.find { |item| item['id'].to_s == contract_number.to_s }
    raise Leaf::Contract::Error, 'not_found' unless found

    found
  end

  def required_connection_id(contract)
    connection_id = contract['connectionId']
    raise Leaf::Contract::Error, 'not_found' if connection_id.blank?

    connection_id
  end

  def customer_payload(contract, contracts, row)
    payload = {
      'name' => contract['name'],
      'registration_status' => registration_status(contract['status']),
      'contracts' => contracts.map { |item| contract_summary(item) }
    }
    connection = connection_attributes_from(contract, row)
    payload['connection'] = connection if connection
    payload
  end

  def contract_summary(contract)
    { 'number' => contract['id'].to_s, 'label' => contract_label(contract) }
  end

  def contract_label(contract)
    street = contract.dig('address', 'street').to_s.presence
    number = contract.dig('address', 'number').to_s.presence
    place = [street, number].compact.join(', ')
    return contract['id'].to_s if place.blank?

    "#{contract['id']} — #{place}"
  end

  def registration_status(status)
    case enum_name(status)
    when 'active' then 'ativo'
    when 'blocked' then 'bloqueado'
    else raise Leaf::Contract::Error, 'leaf_request_failed'
    end
  end

  def enum_name(value)
    value.to_s.strip.downcase
  end

  def blocked_contract?(contract)
    enum_name(contract['status']) == 'blocked'
  end

  def connection_status(value)
    status = enum_name(value)
    return status if Leaf::Contract::CONNECTION_STATUSES.include?(status)

    raise Leaf::Contract::Error, 'leaf_request_failed'
  end

  def connection_row(contract)
    connection_id = contract['connectionId']
    return if connection_id.blank?

    body = @adapter.connection(connection_id)
    rows = Array(body['results'])
    row = rows.find { |item| item['connectionId'].to_s == connection_id.to_s } || rows.first
    return if row.blank?

    row.except('pppoePassword')
  end

  def connection_payload(contract, offline: false)
    row = connection_row(contract)
    attributes = connection_attributes_from(contract, row) || fallback_connection(contract)
    attributes['status'] = 'offline' if offline
    attributes
  rescue Leaf::Contract::Error
    attributes = fallback_connection(contract)
    attributes['status'] = 'offline' if offline
    attributes
  end

  def fallback_connection(contract)
    {
      'status' => 'offline',
      'blocked' => blocked_contract?(contract),
      'technology' => 'pppoe'
    }
  end

  def connection_attributes_from(contract, row)
    return if row.blank?

    gpon = row['gpon']
    attributes = {
      'username' => row['pppoeLogin'],
      'status' => connection_status(row['status']),
      'blocked' => blocked_contract?(contract),
      'technology' => gpon.is_a?(Hash) ? 'ftth' : 'pppoe'
    }
    message = row.dig('auth', 'message')
    attributes['last_log'] = message if message.present?
    onu = onu_from(row, gpon)
    attributes['onu'] = onu if onu
    attributes
  end

  def onu_from(row, gpon)
    return unless gpon.is_a?(Hash)

    serial = row['onuSerial'].to_s
    status = enum_name(gpon['status'])
    return if serial.blank? || Leaf::Contract::ONU_STATUSES.exclude?(status)

    onu = { 'serial' => serial, 'status' => status }
    onu['rx_dbm'] = gpon['rxPower'] unless gpon['rxPower'].nil?
    alarm = gpon['alarm'].to_s
    onu['error'] = alarm if status == 'offline' && alarm.present? && !alarm.casecmp(NO_ALARM).zero?
    onu
  end

  def invoice_rows(body)
    Array(body['results']).first(5).map do |row|
      {
        'id' => row['id'].to_s,
        'description' => row['description'].presence || row['name'].to_s,
        'amount_cents' => amount_cents(row['amount']),
        'due_on' => row['dueDate'].to_s
      }
    end
  end

  def amount_cents(amount)
    return if amount.nil?

    (BigDecimal(amount.to_s) * 100).round.to_i
  end

  def payment_method_names(flags)
    flags = {} unless flags.is_a?(Hash)
    names = []
    names << 'pix' if truthy_flag?(flags, 'pix')
    names << 'boleto' if truthy_flag?(flags, 'bankSlip')
    names << 'card' if truthy_flag?(flags, 'creditCard')
    names
  end

  def truthy_flag?(flags, key)
    flags[key] == true || flags[key.to_sym] == true
  end

  def payment_details(method, body)
    case method
    when 'pix'
      { copy_paste: body['copyPaste'], image_base64: body['qrCode'] }
    when 'boleto'
      details = {}
      details[:pdf_base64] = body['pdf'] if body['pdf'].present?
      details[:payment_url] = body['url'] if body['url'].present?
      details
    when 'card'
      { payment_url: body['url'].presence || body.dig('params', 'url') }
    end
  end

  def digits(value)
    return if value.nil?

    value.to_s.gsub(/\D/, '').presence
  end
end
