class Api::V1::Accounts::Integrations::HooksController < Api::V1::Accounts::Integrations::BaseController
  before_action :fetch_hook, except: [:create]
  before_action :check_authorization
  before_action :ensure_shopify_enabled, if: :shopify_hook?
  before_action :reject_stripe_hook

  def create
    if permitted_params[:app_id] == 'leaf_admin'
      create_leaf_registration
    else
      @hook = Current.account.hooks.create!(permitted_params.except(:inbox_ids))
    end
  end

  def update
    if @hook.app_id == 'leaf_admin'
      sync_leaf_inboxes
    else
      @hook.update!(hook_update_params)
    end
  end

  def process_event
    response = @hook.process_event(params[:event])

    # for cases like an invalid event, or when conversation does not have enough messages
    # for a label suggestion, the response is nil
    if response.nil?
      render json: { message: nil }
    elsif response[:error]
      render json: { error: response[:error] }, status: :unprocessable_entity
    else
      render json: { message: response[:message] }
    end
  end

  def destroy
    @hook.destroy!
    head :ok
  end

  private

  def reject_stripe_hook
    app_id = action_name == 'create' ? permitted_params[:app_id] : @hook.app_id
    return unless app_id == 'stripe'

    # Stripe credentials and connection changes are managed by its OAuth and disconnect endpoints.
    head :not_found
  end

  def fetch_hook
    @hook = Current.account.hooks.find(params[:id])
  end

  def hook_update_params
    permitted_params.slice(:status, :settings).to_h
  end

  def create_leaf_registration
    inbox_ids = leaf_inbox_ids
    return if performed?

    settings = leaf_create_settings
    return if performed?
    return if leaf_conflict?(settings, inbox_ids)

    @hook = Leaf::InboxHooks.create!(account: Current.account, settings: settings, inbox_ids: inbox_ids)
  end

  def sync_leaf_inboxes
    inbox_ids = leaf_inbox_ids
    return if performed?

    settings = leaf_sync_settings
    return if performed?
    return if leaf_conflict?(settings, inbox_ids, anchor: @hook)

    @hook = Leaf::InboxHooks.sync!(account: Current.account, hook: @hook, settings: settings, inbox_ids: inbox_ids)
  end

  def leaf_conflict?(settings, inbox_ids, anchor: nil)
    message = Leaf::InboxHooks.conflict_message(
      account: Current.account,
      settings: settings,
      inbox_ids: inbox_ids,
      anchor: anchor
    )
    return false if message.blank?

    render_could_not_create_error(message)
    true
  end

  def leaf_create_settings
    settings = leaf_setting_values
    return settings if settings['system_url'].present? && settings['api_key'].present?

    render_could_not_create_error('settings are invalid')
    nil
  end

  def leaf_inbox_ids
    raw = params.dig(:hook, :inbox_ids)
    unless raw.is_a?(Array) && raw.any?
      render_could_not_create_error('inbox_ids must be a non-empty array')
      return
    end

    ids = []
    raw.each do |value|
      unless value.is_a?(Integer) && value.positive?
        render_could_not_create_error('inbox_ids must be a non-empty array')
        return
      end
      ids << value
    end
    if ids.uniq.size != ids.size
      render_could_not_create_error('inbox_ids must be a non-empty array')
      return
    end
    if Current.account.inboxes.where(id: ids).count != ids.size
      render_could_not_create_error('inbox_ids must belong to this account')
      return
    end

    ids
  end

  def leaf_sync_settings
    settings = leaf_setting_values
    stored = (@hook.settings || {}).stringify_keys
    settings['system_url'] = stored['system_url'] if settings['system_url'].blank?
    settings['api_key'] = stored['api_key'] if settings['api_key'].blank?
    return settings if settings['system_url'].present? && settings['api_key'].present?

    render_could_not_create_error('settings are invalid')
    nil
  end

  def leaf_setting_values
    raw = params.dig(:hook, :settings)
    source = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : {}
    settings = source.stringify_keys.slice('system_url', 'api_key')
    settings['system_url'] = settings['system_url'].strip if settings['system_url'].is_a?(String)
    settings['api_key'] = settings['api_key'].strip if settings['api_key'].is_a?(String)
    settings
  end

  def permitted_params
    params.require(:hook).permit(:app_id, :inbox_id, :status, inbox_ids: [], settings: {})
  end

  def shopify_hook?
    action_name == 'create' ? permitted_params[:app_id] == 'shopify' : @hook.app_id == 'shopify'
  end

  def ensure_shopify_enabled
    head :not_found unless Shopify::FeatureGate.enabled?(account: Current.account)
  end
end
