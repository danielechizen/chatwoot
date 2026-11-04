<script>
import { isEmptyObject } from '../../../../helper/commons';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useIntegrationHook } from 'dashboard/composables/useIntegrationHook';
import { useBranding } from 'shared/composables/useBranding';
import NewHook from './NewHook.vue';
import SingleIntegrationHooks from './SingleIntegrationHooks.vue';
import MultipleIntegrationHooks from './MultipleIntegrationHooks.vue';
import LeafHookSettings from './LeafHookSettings.vue';
import LeafRegistrationDialogs from './LeafRegistrationDialogs.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

export default {
  components: {
    NewHook,
    SingleIntegrationHooks,
    MultipleIntegrationHooks,
    LeafHookSettings,
    LeafRegistrationDialogs,
    NextButton,
    SettingsLayout,
    BaseSettingsHeader,
  },
  props: {
    integrationId: {
      type: [String, Number],
      required: true,
    },
  },
  setup(props) {
    const { integrationId } = props;
    const { replaceInstallationName } = useBranding();

    const {
      integration,
      isIntegrationMultiple,
      isIntegrationSingle,
      isHookTypeInbox,
    } = useIntegrationHook(integrationId);

    return {
      integration,
      isIntegrationMultiple,
      isIntegrationSingle,
      isHookTypeInbox,
      replaceInstallationName,
    };
  },
  data() {
    return {
      loading: {},
      showAddHookModal: false,
      showDeleteConfirmationPopup: false,
      selectedHook: {},
      alertMessage: '',
      leafSearchQuery: '',
    };
  },
  computed: {
    ...mapGetters({ uiFlags: 'integrations/getUIFlags' }),
    showIntegrationHooks() {
      return !this.uiFlags.isFetching && !isEmptyObject(this.integration);
    },
    showAddButton() {
      return this.showIntegrationHooks && this.isIntegrationMultiple;
    },
    deleteTitle() {
      return this.isHookTypeInbox
        ? this.$t('INTEGRATION_APPS.DELETE.TITLE.INBOX')
        : this.$t('INTEGRATION_APPS.DELETE.TITLE.ACCOUNT');
    },
    deleteMessage() {
      return this.isHookTypeInbox
        ? this.$t('INTEGRATION_APPS.DELETE.MESSAGE.INBOX')
        : this.$t('INTEGRATION_APPS.DELETE.MESSAGE.ACCOUNT');
    },
    confirmText() {
      return this.isHookTypeInbox
        ? this.$t('INTEGRATION_APPS.DELETE.CONFIRM_BUTTON_TEXT.INBOX')
        : this.$t('INTEGRATION_APPS.DELETE.CONFIRM_BUTTON_TEXT.ACCOUNT');
    },
    cancelText() {
      return this.$t('INTEGRATION_APPS.DELETE.CANCEL_BUTTON_TEXT');
    },
    isLeafAdmin() {
      return this.integrationId === 'leaf_admin';
    },
    leafRegistrationCount() {
      const hooks = this.integration?.hooks || [];
      const seen = new Set();
      hooks.forEach(hook => {
        const url = hook.settings?.system_url || '';
        seen.add(url || `hook:${hook.id}`);
      });
      return seen.size;
    },
  },
  mounted() {
    this.$store.dispatch('integrations/get');
  },
  methods: {
    openAddHookModal() {
      this.showAddHookModal = true;
    },
    openLeafAdd() {
      this.$refs.leafDialogs?.openAdd();
    },
    openLeafEdit(registration) {
      this.$refs.leafDialogs?.openEdit(registration);
    },
    openLeafDelete(registration) {
      this.$refs.leafDialogs?.openDelete(registration);
    },
    hideAddHookModal() {
      this.showAddHookModal = false;
    },
    openDeletePopup(response) {
      this.showDeleteConfirmationPopup = true;
      this.selectedHook = response;
    },
    closeDeletePopup() {
      this.showDeleteConfirmationPopup = false;
    },
    async confirmDeletion() {
      try {
        await this.$store.dispatch('integrations/deleteHook', {
          hookId: this.selectedHook.id,
          appId: this.selectedHook.app_id,
        });
        this.alertMessage = this.$t(
          'INTEGRATION_APPS.DELETE.API.SUCCESS_MESSAGE'
        );
        this.closeDeletePopup();
      } catch (error) {
        const errorMessage = error?.response?.data?.message;
        this.alertMessage =
          errorMessage || this.$t('INTEGRATION_APPS.DELETE.API.ERROR_MESSAGE');
      } finally {
        useAlert(this.alertMessage);
      }
    },
  },
};
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :no-records-found="
      isLeafAdmin && showIntegrationHooks && !leafRegistrationCount
    "
    :no-records-message="$t('INTEGRATION_APPS.LEAF.LIST.404')"
  >
    <template v-if="isIntegrationSingle || isLeafAdmin" #header>
      <BaseSettingsHeader
        v-if="isLeafAdmin && integration.name"
        v-model:search-query="leafSearchQuery"
        :title="integration.name"
        :description="replaceInstallationName(integration.description || '')"
        :search-placeholder="$t('INTEGRATION_APPS.LEAF.SEARCH_PLACEHOLDER')"
        :feature-name="integrationId"
        :back-button-label="$t('INTEGRATION_SETTINGS.HEADER')"
      >
        <template v-if="leafRegistrationCount" #count>
          <span class="text-body-main text-n-slate-11">
            {{
              $t('INTEGRATION_APPS.LEAF.COUNT', { n: leafRegistrationCount })
            }}
          </span>
        </template>
        <template #actions>
          <NextButton
            blue
            :label="$t('INTEGRATION_APPS.LEAF.ADD')"
            size="sm"
            @click="openLeafAdd"
          />
        </template>
      </BaseSettingsHeader>
      <BaseSettingsHeader
        v-else-if="isIntegrationSingle"
        :title="integration.name || ''"
        description=""
        :feature-name="integrationId"
        :back-button-label="$t('INTEGRATION_SETTINGS.HEADER')"
      />
    </template>
    <template #body>
      <div v-if="showIntegrationHooks" class="w-full">
        <div v-if="isLeafAdmin">
          <LeafHookSettings
            :hooks="integration.hooks || []"
            :search-query="leafSearchQuery"
            @edit="openLeafEdit"
            @delete="openLeafDelete"
          />
        </div>

        <div v-else-if="isIntegrationMultiple">
          <MultipleIntegrationHooks
            :integration-id="integrationId"
            :show-add-button="showAddButton"
            @add="openAddHookModal"
            @delete="openDeletePopup"
          />
        </div>

        <div v-else-if="isIntegrationSingle">
          <SingleIntegrationHooks
            :integration-id="integrationId"
            @add="openAddHookModal"
            @delete="openDeletePopup"
          />
        </div>
      </div>
    </template>
    <LeafRegistrationDialogs
      v-if="isLeafAdmin"
      ref="leafDialogs"
      :hooks="integration.hooks || []"
    />
    <woot-modal v-model:show="showAddHookModal" :on-close="hideAddHookModal">
      <NewHook :integration-id="integrationId" @close="hideAddHookModal" />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeleteConfirmationPopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="deleteTitle"
      :message="deleteMessage"
      :confirm-text="confirmText"
      :reject-text="cancelText"
    />
  </SettingsLayout>
</template>
