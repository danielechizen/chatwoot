require 'rails_helper'

RSpec.describe 'POST /api/v1/widget/redirect_token', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:origin) { create(:conversation, account: account) }
  let(:visitor) { create(:contact, account: account, identifier: nil, email: nil, phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: visitor, inbox: web_widget.inbox) }
  let(:widget_token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
  end

  def issue_token(extra = {})
    post "/api/v1/accounts/#{account.id}/redirect_tokens",
         params: {
           inbox_id: web_widget.inbox.id,
           identifier: 'fzwa:42',
           ttl_seconds: 86_400,
           origin_display_id: origin.display_id,
           message: 'texto do whatsapp'
         }.merge(extra),
         headers: { api_access_token: admin.access_token.token },
         as: :json
    response.parsed_body['token']
  end

  def resolve(token, auth: widget_token, extra: {})
    post "/api/v1/widget/redirect_token?website_token=#{web_widget.website_token}",
         params: { token: token }.merge(extra),
         headers: { 'X-Auth-Token' => auth },
         as: :json
  end

  def website_conversation(contact)
    contact.conversations.find_by(inbox_id: web_widget.inbox.id)
  end

  it 'creates the website conversation, injects the message once, and burns the token' do
    lead = create(:contact, account: account, identifier: 'fzwa:42', email: nil, phone_number: nil)
    token = issue_token(contact_id: lead.id)

    resolve(token)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['widget_auth_token']).to be_present
    conversation = website_conversation(lead.reload)
    expect(conversation).to be_present
    expect(conversation.messages.incoming.pluck(:content)).to eq(['texto do whatsapp'])
    expect(conversation.contact_inbox.reload.hmac_verified).to be(true)
    expect(conversation.additional_attributes['redirect_origin_display_id']).to eq(origin.display_id)
    webhook = Conversations::EventDataPresenter.new(conversation).webhook_data
    expect(webhook[:redirect_origin_display_id]).to eq(origin.display_id)
  end

  it 'rejects the same token after it has been used' do
    lead = create(:contact, account: account, identifier: 'fzwa:42', email: nil, phone_number: nil)
    token = issue_token(contact_id: lead.id)

    resolve(token)
    conversation = website_conversation(lead.reload)
    resolve(token)

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['error']).to eq('invalid_token')
    expect(RedirectTokens::Store.exists?(token)).to be(false)
    expect(conversation.messages.incoming.pluck(:content)).to eq(['texto do whatsapp'])
  end

  it 'resumes the existing conversation and injects nothing' do
    lead = create(:contact, account: account, identifier: 'fzwa:42', email: nil, phone_number: nil)
    first = issue_token(contact_id: lead.id, message: 'primeira')
    resolve(first)
    conversation = website_conversation(lead.reload)

    second_visitor = create(:contact, account: account, identifier: nil, email: nil, phone_number: nil)
    second_inbox = create(:contact_inbox, contact: second_visitor, inbox: web_widget.inbox)
    second_auth = Widget::TokenService.new(
      payload: { source_id: second_inbox.source_id, inbox_id: web_widget.inbox.id }
    ).generate_token
    second = issue_token(contact_id: lead.id, message: 'segunda')

    resolve(second, auth: second_auth)

    expect(response).to have_http_status(:ok)
    expect(website_conversation(lead.reload).id).to eq(conversation.id)
    expect(conversation.reload.messages.incoming.pluck(:content)).to eq(['primeira'])
  end

  it 'stores a null origin when the token had none, and other conversations omit the key' do
    lead = create(:contact, account: account, identifier: nil, email: nil, phone_number: nil)
    token = issue_token_without_origin(lead)

    resolve(token)

    conversation = website_conversation(lead.reload)
    expect(conversation.additional_attributes.key?('redirect_origin_display_id')).to be(true)
    expect(conversation.additional_attributes['redirect_origin_display_id']).to be_nil
    webhook = Conversations::EventDataPresenter.new(conversation).webhook_data
    expect(webhook.key?(:redirect_origin_display_id)).to be(true)
    expect(webhook[:redirect_origin_display_id]).to be_nil

    other = create(:conversation, account: account, inbox: web_widget.inbox)
    expect(Conversations::EventDataPresenter.new(other).webhook_data.key?(:redirect_origin_display_id)).to be(false)
  end

  it 'creates a new identity when contact_id is omitted' do
    token = issue_token_without_contact

    resolve(token)

    expect(response).to have_http_status(:ok)
    expect(visitor.reload.identifier).to eq('crm-user-42')
    conversation = website_conversation(visitor)
    expect(conversation.contact_id).to eq(visitor.id)
    expect(conversation.messages.incoming.pluck(:content)).to eq(['handover'])
  end

  it 'does not treat the identifier string as the lead' do
    lead = create(:contact, account: account, identifier: nil, email: nil, phone_number: nil, name: 'Lead')
    other = create(:contact, account: account, identifier: 'fzwa:42', name: 'Other')
    token = issue_token(contact_id: lead.id, identifier: 'fzwa:42')

    resolve(token)

    expect(response).to have_http_status(:ok)
    expect(other.reload.identifier).to eq('fzwa:42')
    expect(lead.reload.identifier).to be_nil
    expect(website_conversation(lead).contact_id).to eq(lead.id)
    expect(Contact.find_by(id: visitor.id)).to be_nil
  end

  it 'does not consume a visitor that already has an email, phone, or identifier' do
    lead = create(:contact, account: account, identifier: 'fzwa:42', email: nil, phone_number: nil)
    cases = {
      email: { email: 'prechat@example.com' },
      phone_number: { phone_number: '+15551230000' },
      identifier: { identifier: 'browser-user' }
    }

    cases.each_value do |attrs|
      browser = create(:contact, { account: account, identifier: nil, email: nil, phone_number: nil }.merge(attrs))
      inbox = create(:contact_inbox, contact: browser, inbox: web_widget.inbox)
      auth = Widget::TokenService.new(payload: { source_id: inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
      issued = issue_token(contact_id: lead.id)

      resolve(issued, auth: auth)

      expect(response).to have_http_status(:ok)
      expect(Contact.find_by(id: browser.id)).to be_present
      expect(browser.reload.attributes.slice(*attrs.keys.map(&:to_s))).to eq(attrs.stringify_keys)
      expect(website_conversation(lead.reload).contact_id).to eq(lead.id)
      decoded = Widget::TokenService.new(token: response.parsed_body['widget_auth_token']).decode_token
      expect(ContactInbox.find_by!(source_id: decoded[:source_id]).contact_id).to eq(lead.id)
    end
  end

  it 'returns invalid_token for an unknown token and does not merge' do
    resolve('missing-token')

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['error']).to eq('invalid_token')
    expect(visitor.reload.identifier).to be_nil
    expect(web_widget.inbox.conversations).to be_empty
  end

  def issue_token_without_origin(lead)
    post "/api/v1/accounts/#{account.id}/redirect_tokens",
         params: {
           inbox_id: web_widget.inbox.id,
           identifier: 'fzwa:42',
           contact_id: lead.id,
           ttl_seconds: 86_400,
           message: 'sem origem'
         },
         headers: { api_access_token: admin.access_token.token },
         as: :json
    response.parsed_body['token']
  end

  def issue_token_without_contact
    post "/api/v1/accounts/#{account.id}/redirect_tokens",
         params: {
           inbox_id: web_widget.inbox.id,
           identifier: 'crm-user-42',
           ttl_seconds: 86_400,
           message: 'handover'
         },
         headers: { api_access_token: admin.access_token.token },
         as: :json
    response.parsed_body['token']
  end
end
