root = File.expand_path('../..', __dir__)

checks = [
  ['config/application.rb', 'custom/lib/custom.rb'],
  ['config/application.rb', 'custom/config/initializers/branding.rb'],
  ['config/initializers/01_inject_enterprise_edition_module.rb', 'respond_to?(:const_defined?)'],
  ['config/routes.rb', 'leaf'],
  ['config/integration/apps.yml', 'leaf_admin'],
  ['app/javascript/dashboard/composables/useUISettings.js', 'leaf_customer'],
  ['app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue', 'leaf_customer'],
  ['app/views/widgets/show.html.erb', 'disableBranding: true'],
  ['public/brand-assets/leaf/logo.svg', '<svg'],
  ['custom/app/services/custom/branding.rb', 'INSTALLATION_NAME'],
  ['custom/config/initializers/branding.rb', "top_level_tasks.include?('assets:precompile')"]
]

failed = false

checks.each do |path, snippet|
  contents = File.exist?(File.join(root, path)) ? File.read(File.join(root, path)) : ''
  next if contents.include?(snippet)

  puts "#{path} #{snippet}"
  failed = true
end

exit 1 if failed
