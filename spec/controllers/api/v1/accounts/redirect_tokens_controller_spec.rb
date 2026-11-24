require 'rails_helper'

RSpec.describe 'POST /api/v1/accounts/:id/redirect_tokens', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:origin) { create(:conversation, account: account) }
  let(:headers) { { api_access_token: admin.access_token.token } }

  def issue(extra = {})
    post "/api/v1/accounts/#{account.id}/redirect_tokens",
         params: {
           inbox_id: web_widget.inbox.id,
           identifier: 'fzwa:42',
           ttl_seconds: 86_400,
           origin_display_id: origin.display_id
         }.merge(extra),
         headers: headers,
         as: :json
  end

  def stored_payload(token)
    JSON.parse(Redis::Alfred.get(RedirectTokens::Store.key(token)))
  end

  it 'returns an opaque token and the website url' do
    issue

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['token']).to be_present
    expect(body['expires_in']).to eq(86_400)
    expect(body['website_url']).to eq(web_widget.website_url)
    expect(body['website_url']).to match(%r{\Ahttps://})
  end

  it 'stores the identifier, origin, and ttl without a contact or message' do
    issue

    body = response.parsed_body
    expect(RedirectTokens::Store.ttl(body['token'])).to be_between(86_390, 86_400)
    payload = stored_payload(body['token'])
    expect(payload['identifier']).to eq('fzwa:42')
    expect(payload['origin_display_id']).to eq(origin.display_id)
    expect(payload).not_to have_key('identified_contact_id')
    expect(payload).not_to have_key('message')
  end

  it 'stores the identifier exactly, including the suffixed form' do
    issue(identifier: 'fzwa:42:ab12cd34')

    payload = stored_payload(response.parsed_body['token'])
    expect(payload['identifier']).to eq('fzwa:42:ab12cd34')
  end

  it 'keeps contact_id optional and stores identified_contact_id only when it is sent' do
    lead = create(:contact, account: account, identifier: 'fzwa:42')

    issue
    expect(response).to have_http_status(:ok)
    expect(stored_payload(response.parsed_body['token'])).not_to have_key('identified_contact_id')

    issue(contact_id: lead.id, message: 'oi do whatsapp')
    expect(response).to have_http_status(:ok)
    payload = stored_payload(response.parsed_body['token'])
    expect(payload['identified_contact_id']).to eq(lead.id)
    expect(payload['message']).to eq('oi do whatsapp')
  end

  it 'stores a null origin when the field is absent' do
    params = {
      inbox_id: web_widget.inbox.id,
      identifier: 'crm-user-42',
      ttl_seconds: 86_400
    }
    post "/api/v1/accounts/#{account.id}/redirect_tokens", params: params, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(stored_payload(response.parsed_body['token'])['origin_display_id']).to be_nil
  end

  it 'returns a null website url when the inbox url is not http(s), and still returns a token' do
    web_widget.update!(website_url: 'example.com')

    issue

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['token']).to be_present
    expect(response.parsed_body['website_url']).to be_nil
  end

  it 'does not return a token when origin_display_id is not visible in the account' do
    expect do
      issue(origin_display_id: origin.display_id + 50_000)
    end.not_to change(RedirectTokens::Store, :count)

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).not_to have_key('token')
  end

  it 'does not return a token for an agent' do
    agent = create(:user, account: account, role: :agent)

    expect do
      post "/api/v1/accounts/#{account.id}/redirect_tokens",
           params: {
             inbox_id: web_widget.inbox.id,
             identifier: 'fzwa:42',
             ttl_seconds: 86_400,
             origin_display_id: origin.display_id
           },
           headers: { api_access_token: agent.access_token.token },
           as: :json
    end.not_to change(RedirectTokens::Store, :count)

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).not_to have_key('token')
  end
end
