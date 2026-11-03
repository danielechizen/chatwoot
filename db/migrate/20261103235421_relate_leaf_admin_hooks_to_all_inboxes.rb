class RelateLeafAdminHooksToAllInboxes < ActiveRecord::Migration[7.2]
  def up
    Integrations::Hook.where(app_id: 'leaf_admin', status: :enabled, inbox_id: nil).find_each do |hook|
      inboxes = Inbox.where(account_id: hook.account_id)
      next if inboxes.none?

      settings = leaf_settings(hook)
      Integrations::Hook.transaction do
        inboxes.find_each { |inbox| relate_inbox(hook, inbox, settings) }
        hook.update!(status: :disabled)
      end
    end
  end

  def down
    Integrations::Hook.where(app_id: 'leaf_admin', hook_type: :inbox).find_each(&:destroy!)
    Integrations::Hook.where(app_id: 'leaf_admin', inbox_id: nil).find_each do |hook|
      hook.update!(status: :enabled)
    end
  end

  private

  def relate_inbox(hook, inbox, settings)
    existing = Integrations::Hook.find_by(
      app_id: 'leaf_admin',
      account_id: hook.account_id,
      inbox_id: inbox.id
    )
    if existing
      existing.update!(settings: settings, status: :enabled)
    else
      Integrations::Hook.create!(
        account_id: hook.account_id,
        app_id: 'leaf_admin',
        inbox_id: inbox.id,
        status: :enabled,
        settings: settings
      )
    end
  end

  def leaf_settings(hook)
    (hook.settings || {}).stringify_keys.slice('system_url', 'api_key')
  end
end
