class Api::V1::Accounts::Integrations::LeafController < Api::V1::Accounts::Integrations::BaseController
  APP_ID = 'leaf_admin'.freeze

  def customer
    conversation = conversation_from_params
    return if performed?

    hook = enabled_hook
    return if performed?

    render json: Leaf::Client.build(hook).customer(conversation.contact)
  end

  def payment
    conversation = conversation_from_params
    return if performed?

    hook = enabled_hook
    return if performed?

    invoice_id, payment_method = payment_arguments
    render json: Leaf::Client.build(hook).payment(conversation.contact, invoice_id: invoice_id, method: payment_method)
  rescue Leaf::Contract::Error => e
    render_leaf_error(e)
  end

  def unblock
    conversation = conversation_from_params
    return if performed?

    hook = enabled_hook
    return if performed?

    render json: Leaf::Client.build(hook).unblock(conversation.contact)
  rescue Leaf::Contract::Error => e
    render_leaf_error(e)
  end

  private

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
    return value if value.is_a?(String) && value.present?

    raise Leaf::Contract::Error, 'unknown_invoice'
  end

  def render_leaf_error(error)
    render json: { error: error.code }, status: :unprocessable_entity
  end
end
