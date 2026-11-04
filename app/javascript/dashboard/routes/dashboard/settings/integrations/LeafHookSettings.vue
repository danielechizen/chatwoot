<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import Button from 'dashboard/components-next/button/Button.vue';
import LeafRegistrationForm from './LeafRegistrationForm.vue';

const props = defineProps({
  hooks: {
    type: Array,
    default: () => [],
  },
});

const { t } = useI18n();
const store = useStore();
const showDraft = ref(false);

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

const showNewForm = computed(() => showDraft.value || props.hooks.length === 0);

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

onMounted(() => {
  store.dispatch('inboxes/get');
});

const closeDraft = () => {
  showDraft.value = false;
};
</script>

<template>
  <div class="flex flex-col gap-4 mt-4">
    <div class="flex justify-end">
      <Button
        :label="t('INTEGRATION_APPS.LEAF.ADD')"
        :disabled="showNewForm"
        @click="showDraft = true"
      />
    </div>
    <LeafRegistrationForm
      v-if="showNewForm"
      :inbox-options="optionsFor()"
      :other-urls="urlsExcept('')"
      :allow-cancel="showDraft && props.hooks.length > 0"
      @saved="closeDraft"
      @cancel="closeDraft"
    />
    <LeafRegistrationForm
      v-for="group in groups"
      :key="group.key"
      :hooks="group.hooks"
      :inbox-options="optionsFor(inboxIds(group.hooks))"
      :other-urls="urlsExcept(group.url)"
    />
  </div>
</template>
