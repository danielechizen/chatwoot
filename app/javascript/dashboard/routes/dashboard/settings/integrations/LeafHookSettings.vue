<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { picoSearch } from '@chatwoot/pico-search';
import { BaseTable } from 'dashboard/components-next/table';
import LeafRegistrationRow from './LeafRegistrationRow.vue';

const props = defineProps({
  hooks: {
    type: Array,
    default: () => [],
  },
  searchQuery: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['edit', 'delete']);

const { t } = useI18n();

const enabledInboxNames = hooks =>
  hooks
    .filter(hook => hook.status === true || hook.status === 'enabled')
    .map(hook => hook.inbox?.name)
    .filter(Boolean);

const groups = computed(() => {
  const ordered = [];
  const index = {};
  props.hooks.forEach(hook => {
    const url = hook.settings?.system_url || '';
    const key = url || `hook:${hook.id}`;
    if (index[key] === undefined) {
      index[key] = ordered.length;
      ordered.push({ key, url, hooks: [] });
    }
    ordered[index[key]].hooks.push(hook);
  });
  return ordered.map(group => ({
    ...group,
    inboxLabel: enabledInboxNames(group.hooks).join(', '),
  }));
});

const filteredGroups = computed(() => {
  const query = props.searchQuery.trim();
  if (!query) return groups.value;
  return picoSearch(groups.value, query, ['url', 'inboxLabel']);
});

const tableHeaders = computed(() => [
  t('INTEGRATION_APPS.LEAF.SYSTEM_URL'),
  t('INTEGRATION_APPS.LEAF.ACTIONS'),
]);
</script>

<template>
  <BaseTable
    :headers="tableHeaders"
    :items="filteredGroups"
    :no-data-message="searchQuery ? t('INTEGRATION_APPS.LEAF.NO_RESULTS') : ''"
  >
    <template #row="{ items }">
      <LeafRegistrationRow
        v-for="(registration, index) in items"
        :key="registration.key"
        :index="index"
        :registration="registration"
        @edit="emit('edit', $event)"
        @delete="emit('delete', $event)"
      />
    </template>
  </BaseTable>
</template>
