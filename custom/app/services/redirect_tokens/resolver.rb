class RedirectTokens::Resolver
  ORIGIN_KEY = 'redirect_origin_display_id'.freeze

  Result = Struct.new(:conversation, :auth_token, keyword_init: true)

  def initialize(account:, web_widget:, contact:, contact_inbox:, token:)
    @account = account
    @web_widget = web_widget
    @contact = contact
    @contact_inbox = contact_inbox
    @token = token
  end

  def perform
    payload = load_payload
    return if payload.nil?

    identity = RedirectTokens::Identity.new(
      account: account,
      contact: contact,
      contact_inbox: contact_inbox,
      web_widget: web_widget
    )
    return unless identity.apply(payload)

    conversation = open_conversation(identity, payload)
    Result.new(conversation: conversation, auth_token: auth_token_for(identity.contact_inbox.reload))
  end

  private

  attr_reader :account, :web_widget, :contact, :contact_inbox, :token

  def load_payload
    payload = RedirectTokens::Store.consume(token)
    return if payload.blank?
    return unless payload['account_id'] == account.id && payload['inbox_id'] == web_widget.inbox.id

    payload
  end

  def open_conversation(identity, payload)
    identity.contact_inbox.update!(hmac_verified: true)
    conversation = identity.contact.conversations.where(inbox_id: web_widget.inbox.id).last
    if conversation.present?
      remember_origin(conversation, payload)
    else
      conversation = create_conversation(identity, payload)
      inject_message(conversation, identity.contact, payload)
    end
    conversation.contact_inbox&.update!(hmac_verified: true)
    conversation
  end

  def create_conversation(identity, payload)
    Conversation.create!(
      account_id: account.id,
      inbox_id: web_widget.inbox.id,
      contact_id: identity.contact.id,
      contact_inbox_id: identity.contact_inbox.id,
      additional_attributes: { ORIGIN_KEY => payload['origin_display_id'] }
    )
  end

  def remember_origin(conversation, payload)
    attributes = conversation.additional_attributes.to_h.merge(ORIGIN_KEY => payload['origin_display_id'])
    conversation.update!(additional_attributes: attributes)
  end

  def inject_message(conversation, sender, payload)
    sender.restore_attributes if sender.has_changes_to_save?
    return unless payload.key?('message')

    content = payload['message']
    return if content.blank?

    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: sender,
      content: content,
      message_type: :incoming
    )
  end

  def auth_token_for(session)
    ::Widget::TokenService.new(
      payload: { source_id: session.source_id, inbox_id: session.inbox_id }
    ).generate_token
  end
end
