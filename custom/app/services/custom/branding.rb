class Custom::Branding
  REPLACEMENTS = {
    'INSTALLATION_NAME' => ['Chatwoot', 'Leaf'],
    'BRAND_NAME' => ['Chatwoot', 'Leaf'],
    'LOGO' => ['/brand-assets/logo.svg', '/brand-assets/leaf/logo.svg'],
    'LOGO_DARK' => ['/brand-assets/logo_dark.svg', '/brand-assets/leaf/logo_dark.svg'],
    'LOGO_THUMBNAIL' => ['/brand-assets/logo_thumbnail.svg', '/brand-assets/leaf/logo_thumbnail.svg']
  }.freeze

  def self.apply!
    REPLACEMENTS.each do |name, (default_value, leaf_value)|
      record = InstallationConfig.find_or_initialize_by(name: name)
      current = record.value
      next if current.present? && current != default_value

      record.value = leaf_value
      record.save!
    end
  end
end
