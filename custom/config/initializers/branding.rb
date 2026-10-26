module Custom::ReapplyBranding
  def perform
    branding_only = community_plan? && Custom::Branding.drift_is_leaf_only?
    super
    return unless community_plan?

    disable_saml_on_community_plan
    return unless branding_only

    Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)
  end

  def reconcile_premium_config
    super
    Custom::Branding.apply!
  end

  private

  def community_plan?
    ChatwootHub.pricing_plan == 'community'
  end

  def disable_saml_on_community_plan
    Account.find_each do |account|
      next unless account.feature_enabled?('saml')

      account.disable_features!('saml')
    end
  end
end

module Custom::BrandingBoot
  module_function

  def install
    Rails.application.config.after_initialize do
      apply_branding
      prepend_reconcile
    end
  end

  def apply_branding
    return if precompiling_assets?

    Custom::Branding.apply!
  rescue ActiveRecord::NoDatabaseError
    Rails.logger.debug('Leaf branding skipped: database does not exist')
  rescue ActiveRecord::StatementInvalid => error
    raise unless missing_installation_configs?(error)
  end

  def precompiling_assets?
    File.basename($PROGRAM_NAME) == 'rake' && ARGV.any? { |arg| arg.include?('assets:precompile') }
  end

  def prepend_reconcile
    service = 'Internal::ReconcilePlanConfigService'.safe_constantize
    return unless service
    return if service.ancestors.include?(Custom::ReapplyBranding)

    service.prepend(Custom::ReapplyBranding)
  end

  def missing_installation_configs?(error)
    text = [error.message, error.cause&.message].compact.join("\n")
    text.include?('installation_configs') &&
      text.match?(/does not exist|undefined_table|no such table|doesn't exist/i)
  end
end

Custom::BrandingBoot.install
