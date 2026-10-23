class Leaf::MockAdapter
  FIXTURE_PATH = File.expand_path('fixtures/customers.json', __dir__).freeze

  def initialize(account_id:)
    @account_id = account_id
  end

  def find_customer(identifier:, matched_by:)
    record = locate(identifier, matched_by)
    return if record.blank?

    Leaf::Contract.customer(matched_by: matched_by, customer: presented_customer(record, identifier))
  end

  def match?(identifier:, matched_by:)
    locate(identifier, matched_by).present?
  end

  def payment(identifier:, matched_by:, invoice_id:, payment_method:)
    record = locate(identifier, matched_by)
    raise Leaf::Contract::Error, 'not_found' if record.blank?
    raise Leaf::Contract::Error, 'unknown_invoice' unless open_invoice?(record, invoice_id)

    Leaf::Contract.payment(method: payment_method, invoice_id: invoice_id, details: payment_details(payment_method, invoice_id))
  end

  def unblock(identifier:, matched_by:)
    record = locate(identifier, matched_by)
    raise Leaf::Contract::Error, 'not_found' if record.blank?

    raise Leaf::Contract::Error, 'connection_not_blocked' unless blocked_connection?(record, identifier)

    Rails.cache.write(unblock_cache_key(identifier), true)
    refreshed = presented_customer(record, identifier)
    Leaf::Contract.unblock(name: refreshed.fetch(:name), connection: refreshed.fetch(:connection))
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

  def open_invoice?(record, invoice_id)
    record.fetch('open_invoices').any? { |invoice| invoice['id'] == invoice_id }
  end

  def blocked_connection?(record, identifier)
    presented_customer(record, identifier).fetch(:connection)['blocked'] == true
  end

  def presented_customer(record, identifier)
    {
      name: record.fetch('name'),
      registration_status: record.fetch('registration_status'),
      connection: presented_connection(record, identifier),
      open_invoices: record.fetch('open_invoices')
    }
  end

  def presented_connection(record, identifier)
    connection = record.fetch('connection').deep_dup
    return connection unless unblocked?(identifier)

    connection['blocked'] = false
    connection['status'] = 'online'
    connection['onu']['status'] = 'online' if connection['onu']
    connection
  end

  def unblocked?(identifier)
    Rails.cache.read(unblock_cache_key(identifier)) == true
  end

  def unblock_cache_key(identifier)
    ['leaf-admin', 'unblock', @account_id, identifier].join(':')
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
