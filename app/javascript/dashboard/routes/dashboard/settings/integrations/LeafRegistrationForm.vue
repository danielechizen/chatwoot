<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import LeafAPI from 'dashboard/api/leaf';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';

const props = defineProps({
  hooks: {
    type: Array,
    default: () => [],
  },
  inboxOptions: {
    type: Array,
    default: () => [],
  },
  otherUrls: {
    type: Array,
    default: () => [],
  },
  allowCancel: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['saved', 'cancel']);

const { t } = useI18n();
const store = useStore();
const systemUrl = ref('');
const apiKey = ref('');
const selectedInboxIds = ref([]);
const saving = ref(false);
const testing = ref(false);
const removing = ref(false);
const showRemove = ref(false);

const isNew = computed(() => !props.hooks.some(hook => hook.id));
const canSave = computed(
  () =>
    systemUrl.value.trim() !== '' &&
    selectedInboxIds.value.length > 0 &&
    (isNew.value ? apiKey.value.trim() !== '' : true) &&
    !saving.value
);

const storedSystemUrl = hooks =>
  hooks.find(hook => hook.settings?.system_url)?.settings.system_url || '';

const closeRemove = () => {
  showRemove.value = false;
};

watch(
  () => props.hooks,
  hooks => {
    systemUrl.value = storedSystemUrl(hooks);
    selectedInboxIds.value = hooks
      .filter(hook => hook.status === true || hook.status === 'enabled')
      .map(hook => hook.inbox?.id)
      .filter(id => Number.isInteger(id));
  },
  { immediate: true }
);

const save = async () => {
  if (!canSave.value) return;

  const url = systemUrl.value.trim();
  if (props.otherUrls.includes(url)) {
    useAlert(t('INTEGRATION_APPS.LEAF.SAVE_ERROR'));
    return;
  }

  saving.value = true;
  const settings = { system_url: url, api_key: apiKey.value };
  const inboxIds = [...selectedInboxIds.value];
  try {
    const existing = props.hooks.find(hook => hook.id);
    if (existing) {
      await store.dispatch('integrations/updateHook', {
        hookId: existing.id,
        hookData: { settings, inbox_ids: inboxIds },
      });
    } else {
      await store.dispatch('integrations/createHook', {
        app_id: 'leaf_admin',
        settings,
        inbox_ids: inboxIds,
      });
    }
    apiKey.value = '';
    await store.dispatch('integrations/get');
    useAlert(t('INTEGRATION_APPS.LEAF.SAVE_SUCCESS'));
    emit('saved');
  } catch {
    useAlert(t('INTEGRATION_APPS.LEAF.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};

const testConnection = async () => {
  testing.value = true;
  try {
    await LeafAPI.test(systemUrl.value, apiKey.value);
    useAlert(t('INTEGRATION_APPS.LEAF.TEST_SUCCESS'));
  } catch {
    useAlert(t('INTEGRATION_APPS.LEAF.TEST_ERROR'));
  } finally {
    testing.value = false;
  }
};

const removeRegistration = async () => {
  removing.value = true;
  try {
    const hooks = [...props.hooks];
    for (const hook of hooks) {
      await store.dispatch('integrations/deleteHook', {
        hookId: hook.id,
        appId: 'leaf_admin',
      });
    }
    showRemove.value = false;
    await store.dispatch('integrations/get');
    useAlert(t('INTEGRATION_APPS.DELETE.API.SUCCESS_MESSAGE'));
  } catch {
    useAlert(t('INTEGRATION_APPS.DELETE.API.ERROR_MESSAGE'));
  } finally {
    removing.value = false;
  }
};
</script>

<template>
  <form
    class="flex flex-col gap-4 p-4 outline outline-1 outline-n-container bg-n-card rounded-xl"
    @submit.prevent="save"
  >
    <Input
      v-model="systemUrl"
      :label="t('INTEGRATION_APPS.LEAF.SYSTEM_URL')"
      :placeholder="t('INTEGRATION_APPS.LEAF.SYSTEM_URL')"
    />
    <div class="flex flex-col min-w-0 gap-1">
      <span class="mb-0.5 text-heading-3 text-n-slate-12">
        {{ t('INTEGRATION_APPS.LEAF.INBOXES') }}
      </span>
      <TagMultiSelectComboBox
        v-model="selectedInboxIds"
        :options="inboxOptions"
        :placeholder="t('INTEGRATION_APPS.LEAF.INBOXES_PLACEHOLDER')"
      />
    </div>
    <Input
      v-model="apiKey"
      type="password"
      autocomplete="new-password"
      :label="t('INTEGRATION_APPS.LEAF.API_KEY')"
      :placeholder="
        isNew
          ? t('INTEGRATION_APPS.LEAF.API_KEY')
          : t('INTEGRATION_APPS.LEAF.API_KEY_PLACEHOLDER')
      "
    />
    <div class="flex flex-wrap gap-2">
      <Button
        type="submit"
        :label="t('INTEGRATION_APPS.LEAF.SAVE')"
        :is-loading="saving"
        :disabled="!canSave"
      />
      <Button
        type="button"
        faded
        slate
        :label="t('INTEGRATION_APPS.LEAF.TEST')"
        :is-loading="testing"
        :disabled="testing"
        @click="testConnection"
      />
      <Button
        v-if="isNew && allowCancel"
        type="button"
        faded
        slate
        :label="t('INTEGRATION_APPS.LEAF.CANCEL')"
        @click="emit('cancel')"
      />
      <Button
        v-if="!isNew"
        type="button"
        faded
        ruby
        :label="t('INTEGRATION_APPS.LEAF.REMOVE')"
        :is-loading="removing"
        :disabled="removing"
        @click="showRemove = true"
      />
    </div>
  </form>
  <woot-delete-modal
    v-model:show="showRemove"
    :on-close="closeRemove"
    :on-confirm="removeRegistration"
    :title="t('INTEGRATION_APPS.LEAF.REMOVE_TITLE')"
    :message="t('INTEGRATION_APPS.LEAF.REMOVE_MESSAGE')"
    :confirm-text="t('INTEGRATION_APPS.LEAF.REMOVE')"
    :reject-text="t('INTEGRATION_APPS.LEAF.CANCEL')"
  />
</template>
