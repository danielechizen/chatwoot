class Leaf::HttpAdapter
  # Leaf system URLs often present an invalid or expired certificate.
  # Verification stays off only for the requests this adapter sends there.
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 15
  PAGE_LIMIT = 50
  MAX_PAGES = 20

  def initialize(settings:)
    @settings = settings.is_a?(Hash) ? settings : {}
  end

  def list_contracts(document: nil, phone: nil)
    query = {}
    query[:document] = document if document.present?
    query[:phone] = phone if phone.present?
    collect_results('/integrations/contracts', query)
  end

  def connection(connection_id)
    get('/integrations/customers', query: { connectionId: connection_id, limit: 1 })
  end

  def delayed_billets(contract_id)
    get(
      '/integrations/billets',
      query: { contractId: contract_id, status: 'delayed', limit: 5 }
    )
  end

  def payment(billet_id, type)
    id = billet_id.to_s
    raise Leaf::Contract::Error, 'unknown_invoice' unless id.match?(/\A[1-9]\d*\z/)

    get("/integrations/billets/#{id}/payment", query: { type: type })
  end

  def extend_connection(connection_id)
    post('/integrations/customers/extend', { connectionId: connection_id })
  end

  def clear_mac(connection_id)
    post('/integrations/customers/clear-mac', { connectionId: connection_id })
  end

  def disconnect(connection_id)
    post('/integrations/customers/disconnect', { connectionId: connection_id, force: false })
  end

  def test_connection
    get('/integrations/contracts', query: { limit: 1 })
  end

  private

  def collect_results(path, query)
    page = 1
    rows = []
    loop do
      body = get(path, query: query.merge(page: page, limit: PAGE_LIMIT))
      batch = Array(body['results'])
      rows.concat(batch)
      total = body['total'].to_i
      break if batch.empty? || rows.size >= total || page >= MAX_PAGES

      page += 1
    end
    rows
  end

  def get(path, query:)
    request(:get, path, query: query)
  end

  def post(path, body)
    request(:post, path, body: body)
  end

  def request(verb, path, query: nil, body: nil)
    ensure_credentials!
    options = leaf_request_options
    options[:query] = query if query
    if body
      options[:body] = body.to_json
      options[:headers] = headers.merge('Content-Type' => 'application/json')
    end

    parse(HTTParty.public_send(verb, endpoint(path), options))
  rescue Leaf::Contract::Error
    raise
  rescue HTTParty::Error, SocketError, SystemCallError, Timeout::Error,
         JSON::ParserError, OpenSSL::SSL::SSLError => error
    raise Leaf::Contract::Error.new('leaf_request_failed', error.message)
  end

  def leaf_request_options
    {
      headers: headers,
      verify: false,
      follow_redirects: false,
      open_timeout: OPEN_TIMEOUT,
      timeout: READ_TIMEOUT
    }
  end

  def headers
    { 'x-auth-header' => api_key, 'Accept' => 'application/json' }
  end

  def parse(response)
    body = response.parsed_response
    body = JSON.parse(response.body.to_s) if !body.is_a?(Hash) && response.body.present?
    body = {} unless body.is_a?(Hash)
    return body if response.code.to_i.between?(200, 299) && body['statusCode'] == 1

    raise Leaf::Contract::Error.new(error_code(response, body), body['detailDescription'])
  end

  def error_code(response, body)
    return 'invalid_credentials' if response.code.to_i == 403 || body['detailCode'] == 19

    'leaf_request_failed'
  end

  def endpoint(path)
    "#{base_url}#{path}"
  end

  def base_url
    raw = setting('system_url').to_s.strip.sub(%r{/+\z}, '')
    raise Leaf::Contract::Error, 'invalid_credentials' if raw.blank?

    "#{raw}/api/v2"
  end

  def api_key
    setting('api_key').to_s
  end

  def ensure_credentials!
    raise Leaf::Contract::Error, 'invalid_credentials' if setting('system_url').blank? || api_key.blank?
  end

  def setting(key)
    @settings[key] || @settings[key.to_sym]
  end
end
