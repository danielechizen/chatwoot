class Leaf::Contract
  REGISTRATION_STATUSES = %w[ativo inativo suspenso].freeze
  CONNECTION_STATUSES = %w[online offline].freeze
  ONU_STATUSES = %w[online offline].freeze
  PAYMENT_METHODS = %w[pix boleto card].freeze
  MATCHED_BY = %w[cpf_cnpj phone].freeze

  class << self
    def missing_identifier
      { found: false, reason: 'missing_identifier' }
    end

    def not_found
      { found: false, reason: 'not_found' }
    end

    def customer(matched_by:, customer:)
      {
        found: true,
        matched_by: one_of(matched_by, MATCHED_BY),
        customer: customer_attributes(customer)
      }
    end

    def invoices(contract_number: nil, payment_methods:, open_invoices:)
      payload = {}
      payload[:contract_number] = required_string(contract_number) if contract_number.present?
      payload[:payment_methods] = payment_method_list(payment_methods)
      payload[:open_invoices] = invoice_list(open_invoices)
      payload
    end

    def payment(method:, invoice_id:, details:)
      method_name = one_of(method, PAYMENT_METHODS)
      { method: method_name, invoice_id: required_string(invoice_id) }.merge(payment_body(method_name, details))
    end

    def unblock(name:, connection:)
      {
        unblocked: true,
        name: required_string(name),
        connection: connection_attributes(connection)
      }
    end

    def disconnect(name:, connection:)
      {
        disconnected: true,
        name: required_string(name),
        connection: connection_attributes(connection)
      }
    end

    def clear_mac(name:)
      { mac_cleared: true, name: required_string(name) }
    end

    def connection_test
      { ok: true }
    end

    private

    def payment_body(method_name, details)
      case method_name
      when 'pix' then { pix: pix_attributes(details) }
      when 'boleto' then { boleto: boleto_attributes(details) }
      when 'card' then { card: card_attributes(details) }
      end
    end

    def pix_attributes(details)
      {
        copy_paste: required_string(value(details, :copy_paste)),
        image_base64: required_string(value(details, :image_base64))
      }
    end

    def boleto_attributes(details)
      { pdf_base64: required_string(value(details, :pdf_base64)) }
    end

    def card_attributes(details)
      { payment_url: required_string(value(details, :payment_url)) }
    end

    def customer_attributes(customer)
      attributes = {
        name: required_string(value(customer, :name)),
        registration_status: one_of(value(customer, :registration_status), REGISTRATION_STATUSES),
        connection: connection_attributes(value(customer, :connection))
      }
      contracts = value(customer, :contracts)
      attributes[:contracts] = contract_list(contracts) unless contracts.nil?
      attributes
    end

    def connection_attributes(connection)
      technology = required_string(value(connection, :technology))
      attributes = {}
      username = value(connection, :username)
      attributes[:username] = required_string(username) if username.present?
      attributes[:status] = one_of(value(connection, :status), CONNECTION_STATUSES)
      attributes[:blocked] = required_boolean(value(connection, :blocked))
      attributes[:technology] = technology
      last_log = value(connection, :last_log)
      attributes[:last_log] = required_string(last_log) if last_log.present?
      onu = onu_attributes(technology, value(connection, :onu))
      attributes[:onu] = onu if onu
      attributes
    end

    def onu_attributes(technology, onu)
      return if technology != 'ftth' || !onu.is_a?(Hash)

      attributes = {
        serial: required_string(value(onu, :serial)),
        status: one_of(value(onu, :status), ONU_STATUSES)
      }
      rx = value(onu, :rx_dbm)
      attributes[:rx_dbm] = required_number(rx) unless rx.nil?
      error = value(onu, :error)
      attributes[:error] = required_string(error) if error.present?
      attributes
    end

    def contract_list(list)
      raise ArgumentError, 'invalid leaf contract value' unless list.is_a?(Array)

      list.map { |contract| contract_attributes(contract) }
    end

    def contract_attributes(contract)
      {
        number: required_string(value(contract, :number)),
        label: required_string(value(contract, :label)),
        payment_methods: payment_method_list(value(contract, :payment_methods))
      }
    end

    def payment_method_list(list)
      raise ArgumentError, 'invalid leaf contract value' unless list.is_a?(Array)

      list.map { |method| one_of(method, PAYMENT_METHODS) }
    end

    def invoice_list(list)
      raise ArgumentError, 'invalid leaf contract value' unless list.is_a?(Array)

      list.map { |invoice| invoice_attributes(invoice) }
    end

    def invoice_attributes(invoice)
      {
        id: required_string(value(invoice, :id)),
        description: required_string(value(invoice, :description)),
        amount_cents: required_integer(value(invoice, :amount_cents)),
        due_on: required_string(value(invoice, :due_on))
      }
    end

    def one_of(candidate, allowed)
      return candidate if candidate.is_a?(String) && allowed.include?(candidate)

      raise ArgumentError, 'invalid leaf contract value'
    end

    def required_string(candidate)
      return candidate if candidate.is_a?(String) && candidate.present?

      raise ArgumentError, 'invalid leaf contract value'
    end

    def required_boolean(candidate)
      return candidate if candidate == true || candidate == false

      raise ArgumentError, 'invalid leaf contract value'
    end

    def required_integer(candidate)
      return candidate if candidate.is_a?(Integer)

      raise ArgumentError, 'invalid leaf contract value'
    end

    def required_number(candidate)
      return candidate if candidate.is_a?(Numeric) && candidate.finite?

      raise ArgumentError, 'invalid leaf contract value'
    end

    def value(hash, key)
      return unless hash.is_a?(Hash)
      return hash[key] if hash.key?(key)

      hash[key.to_s] if hash.key?(key.to_s)
    end
  end
end

class Leaf::Contract::Error < StandardError
  attr_reader :code

  def initialize(code)
    @code = code
    super
  end
end
