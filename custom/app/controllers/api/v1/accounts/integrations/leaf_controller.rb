class Api::V1::Accounts::Integrations::LeafController < Api::V1::Accounts::Integrations::BaseController
  APP_ID = 'leaf_admin'.freeze

  def customer
    conversation = conversation_from_params
    return if performed?

    hook = enabled_hook
    return if performed?

    contract_number = optional_contract_number
    return if performed?

    render json: Leaf::Client.build(hook).customer(conversation.contact, contract_number: contract_number)
  rescue Leaf::Contract::Error => e
    render_leaf_error(e)
  end

  def invoices
    conversation = conversation_from_params
    return if performed?

    hook = enabled_hook
    return if performed?

    contract_number = required_contract_number
    return if performed?

    render json: Leaf::Client.build(hook).invoices(conversation.contact, contract_number: contract_number)
  rescue Leaf::Contract::Error => e
    render_leaf_error(e)
  end

  def payment
    conversation = conversation_from_params
    return if performed?

    hook = enabled_hook
    return if performed?

    contract_number = required_contract_number
    return if performed?

    invoice_id, payment_method = payment_arguments
    render json: Leaf::Client.build(hook).payment(
      conversation.contact,
      contract_number: contract_number,
      invoice_id: invoice_id,
      method: payment_method
    )
  rescue Leaf::Contract::Error => e
    render_leaf_error(e)
  end

  def unblock
    perform_connection_action(:unblock)
  end

  def disconnect
    perform_connection_action(:disconnect)
  end

  def clear_mac
    perform_connection_action(:clear_mac)
  end

  def test
    hook = enabled_hook
    return if performed?

    system_url = optional_string_param(:system_url)
    return if performed?

    api_key = optional_string_param(:api_key)
    return if performed?

    settings = (hook.settings || {}).stringify_keys
    settings['system_url'] = system_url if system_url.present?
    settings['api_key'] = api_key if api_key.present?
    render json: Leaf::Client.new(Leaf::HttpAdapter.new(settings: settings)).test_connection
  rescue Leaf::Contract::Error => e
    render_leaf_error(e)
  end

  private

  def perform_connection_action(action)
    conversation = nil
    conversation = conversation_from_params
    return if performed?

    hook = enabled_hook
    return if performed?

    contract_number = required_contract_number
    return if performed?

    payload, detail = Leaf::Client.build(hook).public_send(action, conversation.contact, contract_number: contract_number)
    write_private_note(conversation, detail)
    render json: payload
  rescue Leaf::Contract::Error => e
    write_private_note(conversation, e.detail_description)
    render_leaf_error(e)
  end

  def write_private_note(conversation, detail)
    text = detail.to_s
    return if conversation.blank? || text.blank?

    Messages::MessageBuilder.new(Current.user, conversation, { content: text, private: true }).perform
  end

  def conversation_from_params
    conversation_id = params[:conversation_id]
    unless conversation_id.is_a?(String) && conversation_id.match?(/\A[1-9]\d*\z/)
      render_could_not_create_error('conversation_id must be a positive integer')
      return
    end

    conversation = Current.account.conversations.find_by!(display_id: conversation_id)
    authorize conversation, :show?
    conversation
  end

  def enabled_hook
    hook = Current.account.hooks.find_by(app_id: APP_ID, status: :enabled)
    render json: { error: 'leaf_admin_not_enabled' }, status: :unprocessable_entity if hook.blank?
    hook
  end

  def optional_string_param(key)
    value = params[key]
    return if value.nil? || value == ''
    return value.strip if value.is_a?(String)

    render_could_not_create_error("#{key} must be a string")
    nil
  end

  def optional_contract_number
    value = params[:contract_number]
    return if value.nil? || value == ''
    return value if value.is_a?(String) && value.match?(/\A[1-9]\d*\z/)

    render_could_not_create_error('contract_number must be a string')
    nil
  end

  def required_contract_number
    value = optional_contract_number
    return if performed?
    return value if value.present?

    render_could_not_create_error('contract_number must be a string')
    nil
  end

  def payment_arguments
    [invoice_id_param, payment_method_param]
  end

  def payment_method_param
    value = params[:method]
    return value if value.is_a?(String) && Leaf::Contract::PAYMENT_METHODS.include?(value)

    raise Leaf::Contract::Error, 'unknown_method'
  end

  def invoice_id_param
    value = params[:invoice_id]
    return value if value.is_a?(String) && value.match?(/\A[1-9]\d*\z/)

    raise Leaf::Contract::Error, 'unknown_invoice'
  end

  def render_leaf_error(error)
    render json: { error: error.code }, status: :unprocessable_entity
  end
end
