class RedirectTokens::Issuer
  def initialize(account:, user:, params:)
    @account = account
    @user = user
    @params = params
  end

  def perform
    inbox = find_inbox
    return inbox if failure?(inbox)

    origin = resolve_origin
    return origin if failure?(origin)

    request = validated_request
    return request if failure?(request)

    payload = token_payload(inbox, origin, request)
    token = SecureRandom.urlsafe_base64(32)
    RedirectTokens::Store.write(token, payload, request[:ttl])
    Result.new(token: token, expires_in: request[:ttl], website_url: website_url_for(inbox))
  end

  private

  attr_reader :account, :user, :params

  def validated_request
    identifier = params[:identifier]
    return failure(:unprocessable_entity, 'identifier is required') unless identifier.is_a?(String) && identifier.present?

    ttl = params[:ttl_seconds]
    return failure(:unprocessable_entity, 'ttl_seconds is required') unless ttl.is_a?(Integer) && ttl.positive?

    identified = identified_contact
    return identified if failure?(identified)

    { identifier: identifier, ttl: ttl, identified: identified, message: clone_message }
  end

  def token_payload(inbox, origin, request)
    payload = {
      'account_id' => account.id,
      'inbox_id' => inbox.id,
      'identifier' => request[:identifier],
      'origin_display_id' => origin
    }
    payload['identified_contact_id'] = request[:identified].id if request[:identified]
    payload['message'] = request[:message] if request[:message]
    payload
  end

  def find_inbox
    return failure(:unprocessable_entity, 'inbox_id is required') unless params[:inbox_id].is_a?(Integer)

    inbox = account.inboxes.find_by(id: params[:inbox_id])
    return failure(:not_found, 'inbox not found') unless inbox&.channel_type == 'Channel::WebWidget'

    inbox
  end

  # A present origin that is not visible in this account stops issuance.
  # Dropping the field and continuing would still hand agents a token.
  def resolve_origin
    return nil unless params.key?(:origin_display_id)
    return failure(:not_found, 'conversation not found') unless params[:origin_display_id].is_a?(Integer)

    scope = account.conversations.where(display_id: params[:origin_display_id])
    visible = Conversations::PermissionFilterService.new(scope, user, account).perform
    return failure(:not_found, 'conversation not found') unless visible.exists?

    params[:origin_display_id]
  end

  # contact_id stays optional. Absent keeps the pre-authenticated identity link.
  def identified_contact
    return nil unless params.key?(:contact_id)
    return failure(:unprocessable_entity, 'contact_id is invalid') unless params[:contact_id].is_a?(Integer)

    contact = account.contacts.find_by(id: params[:contact_id])
    return failure(:not_found, 'contact not found') if contact.blank?

    contact
  end

  def clone_message
    return unless params.key?(:message)
    return unless params[:message].is_a?(String)
    return if params[:message].blank?

    params[:message]
  end

  def website_url_for(inbox)
    url = inbox.channel.website_url
    return unless url.is_a?(String)
    return unless url.match?(%r{\Ahttps?://}i)

    url
  end

  def failure(status, error)
    Result.new(error_status: status, error: error)
  end

  def failure?(value)
    value.is_a?(Result) && !value.success?
  end

  class Result
    attr_reader :token, :expires_in, :website_url, :error_status, :error

    def initialize(token: nil, expires_in: nil, website_url: nil, error_status: nil, error: nil)
      @token = token
      @expires_in = expires_in
      @website_url = website_url
      @error_status = error_status
      @error = error
    end

    def success?
      error_status.nil?
    end
  end
end
