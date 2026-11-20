<script setup>
import { BaseTableRow, BaseTableCell } from 'dashboard/components-next/table';
import Button from 'dashboard/components-next/button/Button.vue';
import ShowMore from 'dashboard/components/widgets/ShowMore.vue';

defineProps({
  registration: {
    type: Object,
    required: true,
  },
  index: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['edit', 'delete']);
</script>

<template>
  <BaseTableRow :item="registration">
    <template #default>
      <BaseTableCell>
        <div class="flex gap-2 font-medium break-words text-n-slate-12">
          {{ registration.url }}
        </div>
        <div class="block mt-1 text-sm text-n-slate-11">
          <span class="font-medium">
            {{ $t('INTEGRATION_APPS.LEAF.INBOXES') }}:
          </span>
          <ShowMore :text="registration.inboxLabel" :limit="60" />
        </div>
      </BaseTableCell>

      <BaseTableCell align="end" class="w-24">
        <div class="flex justify-end gap-3 flex-shrink-0">
          <Button
            v-tooltip.top="$t('INTEGRATION_APPS.LEAF.EDIT')"
            icon="i-woot-edit-pen"
            slate
            sm
            @click="emit('edit', registration)"
          />
          <Button
            v-tooltip.top="$t('INTEGRATION_APPS.LEAF.DELETE')"
            icon="i-woot-bin"
            slate
            sm
            class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
            @click="emit('delete', registration, index)"
          />
        </div>
      </BaseTableCell>
    </template>
  </BaseTableRow>
</template>
