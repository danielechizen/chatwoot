class Leaf::Contract
  REGISTRATION_STATUSES = %w[ativo inativo suspenso].freeze
  CONNECTION_STATUSES = %w[online offline].freeze
  ONU_STATUSES = %w[online los dying_gasp offline].freeze
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
      status = one_of(value(customer, :registration_status), REGISTRATION_STATUSES)
      {
        name: required_string(value(customer, :name)),
        registration_status: status,
        connection: connection_attributes(value(customer, :connection)),
        open_invoices: invoice_list(value(customer, :open_invoices))
      }
    end

    def connection_attributes(connection)
      technology = required_string(value(connection, :technology))
      {
        status: one_of(value(connection, :status), CONNECTION_STATUSES),
        blocked: required_boolean(value(connection, :blocked)),
        technology: technology,
        onu: onu_attributes(technology, value(connection, :onu))
      }
    end

    def onu_attributes(technology, onu)
      return if technology != 'ftth' || onu.nil?

      { status: one_of(value(onu, :status), ONU_STATUSES) }
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
