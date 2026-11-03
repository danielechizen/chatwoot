class Leaf::InboxHooks
  APP_ID = 'leaf_admin'.freeze

  def self.sync!(account:, settings:, inbox_ids:)
    kept = nil
    account.transaction do
      kept = inbox_ids.map { |inbox_id| upsert!(account, inbox_id, settings) }
      account.hooks.where(app_id: APP_ID).where.not(id: kept.map(&:id)).find_each(&:destroy!)
    end
    kept.first
  end

  def self.upsert!(account, inbox_id, settings)
    hook = account.hooks.find_by(app_id: APP_ID, inbox_id: inbox_id)
    if hook
      hook.update!(settings: settings, status: :enabled)
      hook
    else
      account.hooks.create!(
        app_id: APP_ID,
        inbox_id: inbox_id,
        status: :enabled,
        settings: settings
      )
    end
  end
  private_class_method :upsert!
end
