<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import LeafAPI from 'dashboard/api/leaf';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  hook: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();
const systemUrl = ref(props.hook.settings?.system_url || '');
const apiKey = ref('');
const saving = ref(false);
const testing = ref(false);

const canSave = computed(() => systemUrl.value.trim() !== '' && !saving.value);

watch(
  () => props.hook.settings?.system_url,
  value => {
    systemUrl.value = value || '';
  }
);

const save = async () => {
  if (!canSave.value) return;

  saving.value = true;
  try {
    await store.dispatch('integrations/updateHook', {
      hookId: props.hook.id,
      hookData: {
        settings: {
          system_url: systemUrl.value.trim(),
          api_key: apiKey.value,
        },
      },
    });
    apiKey.value = '';
    useAlert(t('INTEGRATION_APPS.LEAF.SAVE_SUCCESS'));
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
  <form
    class="flex flex-col gap-4 mt-4 p-4 outline outline-1 outline-n-container bg-n-card rounded-xl"
    @submit.prevent="save"
  >
    <Input
      v-model="systemUrl"
      :label="t('INTEGRATION_APPS.LEAF.SYSTEM_URL')"
      :placeholder="t('INTEGRATION_APPS.LEAF.SYSTEM_URL')"
    />
    <Input
      v-model="apiKey"
      type="password"
      autocomplete="new-password"
      :label="t('INTEGRATION_APPS.LEAF.API_KEY')"
      :placeholder="t('INTEGRATION_APPS.LEAF.API_KEY_PLACEHOLDER')"
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
    </div>
  </form>
</template>
