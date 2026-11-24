require 'rails_helper'

RSpec.describe RedirectTokens::Identity do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account, identifier: nil, email: nil, phone_number: nil) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:identity) do
    described_class.new(account: account, contact: contact, contact_inbox: contact_inbox, web_widget: web_widget)
  end

  it 'drops a rejected identifier before the contact is used as a message sender' do
    create(:contact, account: account, identifier: 'crm-user-42')
    allow(contact).to receive(:save).and_return(false)

    identity.assign_identifier('crm-user-42')

    expect(contact.identifier).to be_nil
    expect(contact.changed?).to be(false)

    allow(contact).to receive(:save).and_call_original
    conversation = create(:conversation, account: account, inbox: web_widget.inbox, contact: contact, contact_inbox: contact_inbox)
    expect do
      conversation.messages.create!(
        account_id: account.id,
        inbox_id: web_widget.inbox.id,
        sender: contact,
        content: 'handover',
        message_type: :incoming
      )
    end.to change { conversation.messages.incoming.count }.by(1)
  end
end
