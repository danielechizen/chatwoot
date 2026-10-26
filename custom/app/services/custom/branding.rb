class Custom::Branding
  PRODUCT_NAME = 'Leaf Agent'
  PREVIOUS_NAMES = ['Chatwoot', 'Leaf'].freeze

  REPLACEMENTS = {
    'INSTALLATION_NAME' => [PREVIOUS_NAMES, PRODUCT_NAME],
    'BRAND_NAME' => [PREVIOUS_NAMES, PRODUCT_NAME],
    'LOGO' => [['/brand-assets/logo.svg'], '/brand-assets/leaf/logo.svg'],
    'LOGO_DARK' => [['/brand-assets/logo_dark.svg'], '/brand-assets/leaf/logo_dark.svg'],
    'LOGO_THUMBNAIL' => [['/brand-assets/logo_thumbnail.svg'], '/brand-assets/leaf/logo_thumbnail.svg'],
    'FAVICON' => [[''], '/brand-assets/leaf/favicon.svg']
  }.freeze

  def self.apply!
    REPLACEMENTS.each do |name, (replaced_values, leaf_value)|
      record = InstallationConfig.find_or_initialize_by(name: name)
      current = record.value
      next if current.present? && !replaced_values.include?(current)

      record.value = leaf_value
      record.save!
    end
  end

  def self.leaf_value(name)
    REPLACEMENTS[name]&.last
  end

  # Community plan warns when a premium installation config is not the Chatwoot
  # default. Leaf branding is the only drift this fork writes on purpose.
  def self.drift_is_leaf_only?
    premium_configs.all? do |config|
      name = config['name']
      default = config['value']
      current = InstallationConfig.find_by(name: name)&.value
      next true if current.nil? || current == default

      leaf_value(name) == current
    end
  end

  def self.premium_configs
    path = Rails.root.join('enterprise/config/premium_installation_config.yml')
    YAML.safe_load(path.read)
  end
end
