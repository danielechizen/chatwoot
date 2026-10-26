require 'rails_helper'

RSpec.describe Internal::ReconcilePlanConfigService do
  describe '#perform' do
    let(:service) { described_class.new }

    context 'when pricing plan is community' do
      before do
        allow(ChatwootHub).to receive(:pricing_plan).and_return('community')
      end

      it 'disables the premium features for accounts' do
        account = create(:account)
        account.enable_features!('disable_branding', 'audit_logs', 'captain_integration')
        account_with_captain = create(:account)
        account_with_captain.enable_features!('captain_integration')
        disable_branding_account = create(:account)
        disable_branding_account.enable_features!('disable_branding')
        service.perform
        expect(account.reload.enabled_features.keys).not_to include(
          'captain_integration', 'disable_branding', 'audit_logs'
        )
        expect(account_with_captain.reload.enabled_features.keys).not_to include('captain_integration')
        expect(disable_branding_account.reload.enabled_features.keys).not_to include('disable_branding')
      end

      it 'creates a premium config reset warning if config was modified' do
        record = InstallationConfig.find_or_initialize_by(name: 'BRAND_URL')
        record.value = 'https://example.test'
        record.save!
        service.perform
        expect(Redis::Alfred.get(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)).to eq('true')
      end

      it 'will not create a premium config reset warning if config is not modified' do
        {
          'INSTALLATION_NAME' => 'Chatwoot',
          'BRAND_NAME' => 'Chatwoot',
          'LOGO' => '/brand-assets/logo.svg',
          'LOGO_DARK' => '/brand-assets/logo_dark.svg',
          'LOGO_THUMBNAIL' => '/brand-assets/logo_thumbnail.svg'
        }.each do |name, value|
          record = InstallationConfig.find_or_initialize_by(name: name)
          record.value = value
          record.save!
        end
        service.perform
        expect(Redis::Alfred.get(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)).to be_nil
      end

      it 'updates the premium configs to default and Leaf Agent replaces the Chatwoot brand' do
        installation_name = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_NAME')
        installation_name.value = 'custom-name'
        installation_name.save!
        logo = InstallationConfig.find_or_initialize_by(name: 'LOGO')
        logo.value = '/custom-path/logo.svg'
        logo.save!
        service.perform
        expect(InstallationConfig.find_by(name: 'INSTALLATION_NAME').value).to eq('Leaf Agent')
        expect(InstallationConfig.find_by(name: 'LOGO').value).to eq('/brand-assets/leaf/logo.svg')
      end
    end

    context 'when pricing plan is not community' do
      before do
        allow(ChatwootHub).to receive(:pricing_plan).and_return('enterprise')
      end

      it 'unset premium config warning on upgrade' do
        Redis::Alfred.set(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING, true)
        service.perform
        expect(Redis::Alfred.get(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)).to be_nil
      end

      it 'does not disable the premium features for accounts' do
        account = create(:account)
        account.enable_features!('disable_branding', 'audit_logs', 'captain_integration')
        account_with_captain = create(:account)
        account_with_captain.enable_features!('captain_integration')
        disable_branding_account = create(:account)
        disable_branding_account.enable_features!('disable_branding')
        service.perform
        expect(account.reload.enabled_features.keys).to include(
          'captain_integration', 'disable_branding', 'audit_logs'
        )
        expect(account_with_captain.reload.enabled_features.keys).to include('captain_integration')
        expect(disable_branding_account.reload.enabled_features.keys).to include('disable_branding')
      end

      it 'does not update the LOGO config' do
        installation_name = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_NAME')
        installation_name.value = 'custom-name'
        installation_name.save!
        logo = InstallationConfig.find_or_initialize_by(name: 'LOGO')
        logo.value = '/custom-path/logo.svg'
        logo.save!
        service.perform
        expect(InstallationConfig.find_by(name: 'INSTALLATION_NAME').value).to eq('custom-name')
        expect(InstallationConfig.find_by(name: 'LOGO').value).to eq('/custom-path/logo.svg')
      end
    end
  end
end
