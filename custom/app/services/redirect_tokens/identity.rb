class RedirectTokens::Identity
  def initialize(account:, contact:, contact_inbox:, web_widget:)
    @account = account
    @contact = contact
    @contact_inbox = contact_inbox
    @web_widget = web_widget
  end

  attr_reader :contact, :contact_inbox

  def apply(payload)
    if payload.key?('identified_contact_id')
      apply_identified(payload['identified_contact_id'])
    else
      apply_identifier(payload['identifier'])
    end
  end

  # The identifier string is not proof of who the browser is. A failed write
  # must not stay on the in-memory contact: Message.create!(sender:) validates
  # that object again.
  def assign_identifier(identifier)
    return if contact.identifier == identifier

    contact.identifier = identifier
    return if contact.save

    contact.restore_attributes
  end

  private

  attr_reader :account, :web_widget

  def apply_identified(contact_id)
    lead = account.contacts.find_by(id: contact_id)
    return false if lead.blank?
    return true if contact.id == lead.id

    if anonymous_visitor?(contact)
      merge_visitor_into(lead)
    else
      open_session_for(lead)
    end
    true
  end

  def apply_identifier(identifier)
    return true if identifier.blank?

    existing = account.contacts.find_by(identifier: identifier)
    if existing.present? && existing.id != contact.id
      merge_visitor_into(existing) if anonymous_visitor?(contact)
      return true
    end

    assign_identifier(identifier)
    true
  end

  # ContactIdentifyAction merges on identifier, email, and phone_number.
  # A pre-chat contact has email or phone and must not be consumed as anonymous.
  def anonymous_visitor?(record)
    record.identifier.blank? && record.email.blank? && record.phone_number.blank?
  end

  def merge_visitor_into(lead)
    @contact = ContactMergeAction.new(
      account: account,
      base_contact: lead,
      mergee_contact: contact
    ).perform
    @contact_inbox.reload
  end

  def open_session_for(lead)
    fresh_inbox = web_widget.create_contact_inbox({})
    @contact = ContactMergeAction.new(
      account: account,
      base_contact: lead,
      mergee_contact: fresh_inbox.contact
    ).perform
    @contact_inbox = fresh_inbox.reload
  end
end
