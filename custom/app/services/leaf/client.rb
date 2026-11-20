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

  def customer(contact, contract_number: nil, customer_id: nil)
    contracts, matched_by = contracts_for(contact)
    return Leaf::Contract.missing_identifier if matched_by.nil?
    return Leaf::Contract.not_found if contracts.empty?

    group = selected_group(contracts, customer_id)
    rows = group[:contracts]
    contract = select_contract(rows, contract_number)
    Leaf::Contract.customer(
      matched_by: matched_by,
      customer_id: group[:id],
      customers: customer_options(contracts),
      customer: customer_payload(contract, rows, connection_row(contract), group[:name])
    )
  end

  def invoices(contact, contract_number:, customer_id: nil)
    contract = owned_contract(contact, contract_number, customer_id: customer_id)
    body = @adapter.delayed_billets(contract['id'])
    Leaf::Contract.invoices(
      contract_number: contract['id'].to_s,
      payment_methods: payment_method_names(body['paymentMethods']),
      open_invoices: invoice_rows(body)
    )
  end

  def payment(contact, contract_number:, invoice_id:, method:, customer_id: nil)
    contract = owned_contract(contact, contract_number, customer_id: customer_id)
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

  def unblock(contact, contract_number:, customer_id: nil)
    contract = owned_contract(contact, contract_number, customer_id: customer_id)
    with_connection_name(contract) do
      @adapter.extend_connection(required_connection_id(contract))
      Leaf::Contract.unblock(name: subject_name(contract), connection: connection_payload(contract))
    end
  end

  def disconnect(contact, contract_number:, customer_id: nil)
    contract = owned_contract(contact, contract_number, customer_id: customer_id)
    with_connection_name(contract) do
      @adapter.disconnect(required_connection_id(contract))
      Leaf::Contract.disconnect(
        name: subject_name(contract),
        connection: connection_payload(contract, offline: true)
      )
    end
  end

  def clear_mac(contact, contract_number:, customer_id: nil)
    contract = owned_contract(contact, contract_number, customer_id: customer_id)
    with_connection_name(contract) do
      @adapter.clear_mac(required_connection_id(contract))
      Leaf::Contract.clear_mac(name: subject_name(contract))
    end
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

  def owned_contract(contact, contract_number, customer_id: nil)
    raise Leaf::Contract::Error, 'not_found' if contract_number.blank?

    contracts, matched_by = contracts_for(contact)
    raise Leaf::Contract::Error, 'missing_identifier' if matched_by.nil?

    rows = customer_id.present? ? selected_group(contracts, customer_id)[:contracts] : Array(contracts)
    found = rows.find { |item| item['id'].to_s == contract_number.to_s }
    raise Leaf::Contract::Error, 'not_found' unless found

    found
  end

  def selected_group(contracts, customer_id)
    groups = group_contracts(contracts)
    raise Leaf::Contract::Error, 'not_found' if groups.empty?

    return groups.first if customer_id.blank?

    found = groups.find { |group| group[:id] == customer_id.to_s }
    raise Leaf::Contract::Error, 'not_found' unless found

    found
  end

  def customer_options(contracts)
    groups = group_contracts(contracts)
    return if groups.size < 2

    groups.map { |group| { id: group[:id], name: group[:name] } }
  end

  def group_contracts(contracts)
    ordered = []
    index = {}
    contracts.each do |contract|
      key = group_key(contract)
      unless index.key?(key)
        index[key] = ordered.length
        ordered << { id: group_public_id(contract, key), name: group_name(contract), contracts: [] }
      end
      ordered[index[key]][:contracts] << contract
    end
    ordered
  end

  def group_key(contract)
    external = external_customer_id(contract)
    return "ext:#{external}" if external.present?

    document = contract_document(contract)
    name = stripped_name(contract['name'])
    return "doc:#{document}|#{name}" if document.present? && name.present?
    return "name:#{name}" if name.present?

    "row:#{contract['id']}"
  end

  def external_customer_id(contract)
    [
      contract['customerId'],
      contract['clientId'],
      contract.dig('customer', 'id'),
      contract.dig('customer', 'customerId')
    ].each do |value|
      next unless value.is_a?(String) || value.is_a?(Numeric)

      text = value.to_s.strip
      return text if text.present?
    end
    nil
  end

  def contract_document(contract)
    raw = contract['document'].presence ||
          contract['cpfCnpj'].presence ||
          contract['cpf_cnpj'].presence ||
          contract.dig('customer', 'document').presence
    digits(raw)
  end

  def stripped_name(name)
    name.to_s.gsub(/\s+/, ' ').strip
  end

  def group_name(contract)
    stripped_name(contract['name']).presence || contract['id'].to_s
  end

  def group_public_id(contract, key)
    return key if key.match?(/\A[[:print:]]{1,200}\z/)

    "row:#{contract['id']}"
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

  def customer_payload(contract, contracts, row, name = nil)
    payload = {
      'name' => name.presence || group_name(contract),
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
        'due_on' => row['dueDate'].to_s,
        'status' => invoice_status(row['status'])
      }
    end
  end

  def invoice_status(status)
    enum_name(status) == 'delayed' ? 'atrasada' : 'pendente'
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

  def subject_name(contract)
    contract['name'].presence || connection_login(contract)
  end

  def connection_login(contract)
    return if contract['connectionId'].blank?

    connection_row(contract)&.[]('pppoeLogin').presence
  rescue Leaf::Contract::Error
    nil
  end

  def with_connection_name(contract)
    yield
  rescue Leaf::Contract::Error => error
    raise error.with_name(subject_name(contract))
  end

  def digits(value)
    return if value.nil?

    value.to_s.gsub(/\D/, '').presence
  end
end
