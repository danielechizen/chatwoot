<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import LeafRegistrationForm from './LeafRegistrationForm.vue';

const props = defineProps({
  hooks: {
    type: Array,
    default: () => [],
  },
});

const { t } = useI18n();
const store = useStore();
const showAdd = ref(false);
const showEdit = ref(false);
const showDelete = ref(false);
const selected = ref(null);

const inboxes = computed(() => store.getters['inboxes/getInboxes'] || []);

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
  return ordered;
});

const inboxIds = hooks =>
  hooks.map(hook => hook.inbox?.id).filter(id => Number.isInteger(id));

const optionsFor = (ownIds = []) => {
  const taken = new Set(
    inboxIds(props.hooks).filter(id => !ownIds.includes(id))
  );
  return inboxes.value
    .filter(inbox => !taken.has(inbox.id))
    .map(inbox => ({ value: inbox.id, label: inbox.name }));
};

const urlsExcept = url =>
  groups.value.map(group => group.url).filter(item => item && item !== url);

const openAdd = () => {
  showAdd.value = true;
};

const hideAdd = () => {
  showAdd.value = false;
};

const openEdit = registration => {
  selected.value = registration;
  showEdit.value = true;
};

const hideEdit = () => {
  showEdit.value = false;
};

const openDelete = registration => {
  selected.value = registration;
  showDelete.value = true;
};

const closeDelete = () => {
  showDelete.value = false;
};

const confirmDelete = async () => {
  const hooks = [...(selected.value?.hooks || [])];
  closeDelete();
  try {
    await hooks.reduce(
      (chain, hook) =>
        chain.then(() =>
          store.dispatch('integrations/deleteHook', {
            hookId: hook.id,
            appId: 'leaf_admin',
          })
        ),
      Promise.resolve()
    );
    await store.dispatch('integrations/get');
    useAlert(t('INTEGRATION_APPS.DELETE.API.SUCCESS_MESSAGE'));
  } catch {
    useAlert(t('INTEGRATION_APPS.DELETE.API.ERROR_MESSAGE'));
  }
};

onMounted(() => {
  store.dispatch('inboxes/get');
});

defineExpose({ openAdd, openEdit, openDelete });
</script>

<template>
  <woot-modal v-model:show="showAdd" :on-close="hideAdd">
    <div v-if="showAdd" class="flex flex-col h-auto overflow-auto">
      <woot-modal-header :header-title="t('INTEGRATION_APPS.LEAF.ADD')" />
      <LeafRegistrationForm
        :inbox-options="optionsFor()"
        :other-urls="urlsExcept('')"
        @saved="hideAdd"
        @cancel="hideAdd"
      />
    </div>
  </woot-modal>

  <woot-modal v-model:show="showEdit" :on-close="hideEdit">
    <div v-if="showEdit && selected" class="flex flex-col h-auto overflow-auto">
      <woot-modal-header
        :header-title="t('INTEGRATION_APPS.LEAF.EDIT_TITLE')"
      />
      <LeafRegistrationForm
        :hooks="selected.hooks"
        :inbox-options="optionsFor(inboxIds(selected.hooks))"
        :other-urls="urlsExcept(selected.url)"
        @saved="hideEdit"
        @cancel="hideEdit"
      />
    </div>
  </woot-modal>

  <woot-delete-modal
    v-model:show="showDelete"
    :on-close="closeDelete"
    :on-confirm="confirmDelete"
    :title="t('INTEGRATION_APPS.LEAF.REMOVE_TITLE')"
    :message="
      t('INTEGRATION_APPS.LEAF.REMOVE_MESSAGE', {
        systemUrl: selected?.url || '',
      })
    "
    :confirm-text="t('INTEGRATION_APPS.LEAF.REMOVE')"
    :reject-text="t('INTEGRATION_APPS.LEAF.CANCEL')"
  />
</template>
