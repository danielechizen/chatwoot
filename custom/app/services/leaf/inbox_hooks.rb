class Leaf::InboxHooks
  APP_ID = 'leaf_admin'.freeze

  def self.create!(account:, settings:, inbox_ids:)
    created = nil
    account.transaction do
      created = inbox_ids.map { |inbox_id| build!(account, inbox_id, settings) }
    end
    created.first
  end

  def self.sync!(account:, hook:, settings:, inbox_ids:)
    kept = nil
    account.transaction do
      group = registration_hooks(account, hook)
      kept = inbox_ids.map { |inbox_id| upsert!(account, group, inbox_id, settings) }
      kept_ids = kept.map(&:id)
      group.each { |existing| existing.destroy! unless kept_ids.include?(existing.id) }
    end
    kept.first
  end

  def self.conflict_message(account:, settings:, inbox_ids:, anchor: nil)
    url = system_url_value(settings)
    original_url = anchor ? system_url(anchor) : nil
    hooks = account.hooks.where(app_id: APP_ID).to_a
    group_ids = if anchor
                  hooks.select { |candidate| system_url(candidate) == original_url }.map(&:id)
                else
                  []
                end
    others = hooks.reject { |candidate| group_ids.include?(candidate.id) }
    return 'system_url is already used' if others.any? { |candidate| system_url(candidate) == url }
    return 'inbox is already assigned' if others.any? { |candidate| inbox_ids.include?(candidate.inbox_id) }

    nil
  end

  def self.system_url(hook)
    system_url_value(hook.settings)
  end

  def self.system_url_value(settings)
    settings.to_h.stringify_keys['system_url'].to_s
  end

  def self.registration_hooks(account, hook)
    url = system_url(hook)
    account.hooks.where(app_id: APP_ID).select { |candidate| system_url(candidate) == url }
  end

  def self.upsert!(account, group, inbox_id, settings)
    existing = group.find { |candidate| candidate.inbox_id == inbox_id }
    if existing
      existing.update!(settings: settings, status: :enabled)
      existing
    else
      build!(account, inbox_id, settings)
    end
  end

  def self.build!(account, inbox_id, settings)
    account.hooks.create!(
      app_id: APP_ID,
      inbox_id: inbox_id,
      status: :enabled,
      settings: settings
    )
  end

  private_class_method :registration_hooks, :upsert!, :build!, :system_url_value
end
