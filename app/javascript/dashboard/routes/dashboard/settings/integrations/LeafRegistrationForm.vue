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
});

const emit = defineEmits(['saved', 'cancel']);

const { t } = useI18n();
const store = useStore();
const systemUrl = ref('');
const apiKey = ref('');
const selectedInboxIds = ref([]);
const saving = ref(false);
const testing = ref(false);

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
</script>

<template>
  <form class="flex flex-col w-full gap-4" @submit.prevent="save">
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
    <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
      <Button
        type="button"
        faded
        slate
        :label="t('INTEGRATION_APPS.LEAF.CANCEL')"
        @click="emit('cancel')"
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
        type="submit"
        :label="t('INTEGRATION_APPS.LEAF.SAVE')"
        :is-loading="saving"
        :disabled="!canSave"
      />
    </div>
  </form>
</template>
