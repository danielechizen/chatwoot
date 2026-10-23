class Leaf::Client
  def self.build(hook)
    # system_url and api_key are ignored until an HTTP adapter replaces the mock.
    # The controller already requires an enabled leaf_admin hook.
    new(Leaf::MockAdapter.new(account_id: hook.account_id))
  end

  def initialize(adapter)
    @adapter = adapter
  end

  def customer(contact)
    cpf = cpf_cnpj(contact)
    phone = phone_number(contact)
    return Leaf::Contract.missing_identifier if cpf.nil? && phone.nil?

    find_customer(cpf, 'cpf_cnpj') || find_customer(phone, 'phone') || Leaf::Contract.not_found
  end

  def payment(contact, invoice_id:, method:)
    identifier, matched_by = matched_identifier(contact)
    @adapter.payment(identifier: identifier, matched_by: matched_by, invoice_id: invoice_id, payment_method: method)
  end

  def unblock(contact)
    identifier, matched_by = matched_identifier(contact)
    @adapter.unblock(identifier: identifier, matched_by: matched_by)
  end

  private

  def matched_identifier(contact)
    cpf = cpf_cnpj(contact)
    phone = phone_number(contact)
    raise Leaf::Contract::Error, 'missing_identifier' if cpf.nil? && phone.nil?

    match = first_match(cpf, phone)
    raise Leaf::Contract::Error, 'not_found' unless match

    match
  end

  def first_match(cpf, phone)
    return [cpf, 'cpf_cnpj'] if identifier_match?(cpf, 'cpf_cnpj')
    return [phone, 'phone'] if identifier_match?(phone, 'phone')

    nil
  end

  def find_customer(identifier, matched_by)
    return if identifier.nil?

    @adapter.find_customer(identifier: identifier, matched_by: matched_by)
  end

  def identifier_match?(identifier, matched_by)
    return false if identifier.nil?

    @adapter.match?(identifier: identifier, matched_by: matched_by)
  end

  def cpf_cnpj(contact)
    present_string(contact.custom_attributes&.[]('cpf_cnpj'))
  end

  def phone_number(contact)
    present_string(contact.phone_number)
  end

  def present_string(value)
    return unless value.is_a?(String)

    value.presence
  end
end
