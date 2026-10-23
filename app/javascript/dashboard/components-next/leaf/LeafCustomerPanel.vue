<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import LeafAPI from 'dashboard/api/leaf';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const { t } = useI18n();
const store = useStore();
const currentUser = useMapGetter('getCurrentUser');
const { run, isPending } = useAbortableRequest();

const lookup = ref(null);
const loadError = ref('');
const actionError = ref('');
const selectedInvoiceId = ref('');
const payingMethod = ref('');
const unblocking = ref(false);

const customer = computed(() => lookup.value?.customer || null);
const connection = computed(() => customer.value?.connection || null);
const showOnu = computed(
  () => connection.value?.technology === 'ftth' && !!connection.value?.onu
);
const canUnblock = computed(() => connection.value?.blocked === true);
const busy = computed(() => unblocking.value || payingMethod.value !== '');

const statusLabel = key => {
  switch (key) {
    case 'ativo':
      return t('CONVERSATION_SIDEBAR.LEAF.STATUS.ATIVO');
    case 'inativo':
      return t('CONVERSATION_SIDEBAR.LEAF.STATUS.INATIVO');
    case 'suspenso':
      return t('CONVERSATION_SIDEBAR.LEAF.STATUS.SUSPENSO');
    case 'online':
      return t('CONVERSATION_SIDEBAR.LEAF.STATUS.ONLINE');
    case 'offline':
      return t('CONVERSATION_SIDEBAR.LEAF.STATUS.OFFLINE');
    case 'los':
      return t('CONVERSATION_SIDEBAR.LEAF.STATUS.LOS');
    case 'dying_gasp':
      return t('CONVERSATION_SIDEBAR.LEAF.STATUS.DYING_GASP');
    default:
      return t('CONVERSATION_SIDEBAR.LEAF.STATUS.UNKNOWN');
  }
};

const messageFor = error => {
  const code = error?.response?.data?.error;
  if (code === 'leaf_admin_not_enabled') {
    return t('CONVERSATION_SIDEBAR.LEAF.ERRORS.DISABLED');
  }
  if (code === 'unknown_invoice') {
    return t('CONVERSATION_SIDEBAR.LEAF.ERRORS.UNKNOWN_INVOICE');
  }
  if (code === 'unknown_method') {
    return t('CONVERSATION_SIDEBAR.LEAF.ERRORS.UNKNOWN_METHOD');
  }
  if (code === 'connection_not_blocked') {
    return t('CONVERSATION_SIDEBAR.LEAF.ERRORS.NOT_BLOCKED');
  }
  if (code === 'not_found') {
    return t('CONVERSATION_SIDEBAR.LEAF.NOT_FOUND');
  }
  if (code === 'missing_identifier') {
    return t('CONVERSATION_SIDEBAR.LEAF.MISSING_IDENTIFIER');
  }
  return t('CONVERSATION_SIDEBAR.LEAF.ERROR');
};

const formatAmount = cents =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(Number(cents) / 100);

const formatDueOn = value => {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value || '');
  if (!match) return value || '';

  const date = new Date(
    Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
  );
  return new Intl.DateTimeFormat(undefined, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(date);
};

const fileFromBase64 = (base64, filename, mimeType) => {
  const binary = atob(base64);
  const bytes = Uint8Array.from(binary, char => char.charCodeAt(0));
  return new File([bytes], filename, { type: mimeType });
};

const pendingSender = () => ({
  name: currentUser.value?.name,
  thumbnail: currentUser.value?.avatar_url,
});

const paymentMessage = data => {
  const base = {
    conversationId: props.conversationId,
    private: false,
    sender: pendingSender(),
  };

  if (data.method === 'pix') {
    const file = fileFromBase64(data.pix.image_base64, 'pix.png', 'image/png');
    return {
      ...base,
      message: data.pix.copy_paste,
      files: [file],
      file,
    };
  }

  if (data.method === 'boleto') {
    const file = fileFromBase64(
      data.boleto.pdf_base64,
      'boleto.pdf',
      'application/pdf'
    );
    return {
      ...base,
      message: '',
      files: [file],
      file,
    };
  }

  return { ...base, message: data.card.payment_url };
};

const load = async () => {
  loadError.value = '';
  actionError.value = '';
  lookup.value = null;
  selectedInvoiceId.value = '';
  try {
    const response = await run(signal =>
      LeafAPI.customer(props.conversationId, signal)
    );
    if (response) lookup.value = response.data;
  } catch (error) {
    loadError.value = messageFor(error);
  }
};

const toggleInvoice = invoiceId => {
  if (busy.value) return;
  selectedInvoiceId.value =
    selectedInvoiceId.value === invoiceId ? '' : invoiceId;
};

const sendPayment = async (invoice, method) => {
  if (busy.value) return;

  actionError.value = '';
  payingMethod.value = method;
  try {
    const { data } = await LeafAPI.payment(
      props.conversationId,
      invoice.id,
      method
    );
    await store.dispatch('createPendingMessageAndSend', paymentMessage(data));
    selectedInvoiceId.value = '';
  } catch (error) {
    actionError.value = messageFor(error);
  } finally {
    payingMethod.value = '';
  }
};

const unblockNote = data => {
  const status = statusLabel(data.connection.status);
  if (!data.connection.onu) {
    return t('CONVERSATION_SIDEBAR.LEAF.UNBLOCK_NOTE', {
      name: data.name,
      status,
    });
  }

  return t('CONVERSATION_SIDEBAR.LEAF.UNBLOCK_NOTE_WITH_ONU', {
    name: data.name,
    status,
    onu: statusLabel(data.connection.onu.status),
  });
};

const applyUnblock = data => {
  if (!lookup.value?.customer) return;

  lookup.value = {
    ...lookup.value,
    customer: {
      ...lookup.value.customer,
      name: data.name,
      connection: data.connection,
    },
  };
};

const unblockConnection = async () => {
  if (busy.value) return;

  actionError.value = '';
  unblocking.value = true;
  try {
    const { data } = await LeafAPI.unblock(props.conversationId);
    applyUnblock(data);
    try {
      await store.dispatch('createPendingMessageAndSend', {
        conversationId: props.conversationId,
        message: unblockNote(data),
        private: true,
        sender: pendingSender(),
      });
    } catch {
      actionError.value = t('CONVERSATION_SIDEBAR.LEAF.NOTE_ERROR');
    }
  } catch (error) {
    actionError.value = messageFor(error);
  } finally {
    unblocking.value = false;
  }
};

watch(() => props.conversationId, load, { immediate: true });
</script>

<template>
  <div class="flex flex-col gap-3 px-4 py-3 text-sm text-n-slate-12">
    <Spinner v-if="isPending || (!lookup && !loadError)" class="mx-auto" />
    <p v-else-if="loadError" role="alert" class="m-0 text-n-ruby-11">
      {{ loadError }}
    </p>
    <p
      v-else-if="lookup.reason === 'missing_identifier'"
      class="m-0 text-n-slate-11"
    >
      {{ $t('CONVERSATION_SIDEBAR.LEAF.MISSING_IDENTIFIER') }}
    </p>
    <p v-else-if="!lookup.found" class="m-0 text-n-slate-11">
      {{ $t('CONVERSATION_SIDEBAR.LEAF.NOT_FOUND') }}
    </p>
    <template v-else-if="customer">
      <dl class="flex flex-col gap-2 m-0">
        <div class="flex flex-col gap-0.5">
          <dt class="text-xs text-n-slate-11">
            {{ $t('CONVERSATION_SIDEBAR.LEAF.NAME') }}
          </dt>
          <dd class="m-0">{{ customer.name }}</dd>
        </div>
        <div class="flex flex-col gap-0.5">
          <dt class="text-xs text-n-slate-11">
            {{ $t('CONVERSATION_SIDEBAR.LEAF.REGISTRATION') }}
          </dt>
          <dd class="m-0">{{ statusLabel(customer.registration_status) }}</dd>
        </div>
        <div class="flex flex-col gap-0.5">
          <dt class="text-xs text-n-slate-11">
            {{ $t('CONVERSATION_SIDEBAR.LEAF.CONNECTION') }}
          </dt>
          <dd class="m-0">{{ statusLabel(connection.status) }}</dd>
        </div>
        <div v-if="showOnu" class="flex flex-col gap-0.5">
          <dt class="text-xs text-n-slate-11">
            {{ $t('CONVERSATION_SIDEBAR.LEAF.ONU') }}
          </dt>
          <dd class="m-0">{{ statusLabel(connection.onu.status) }}</dd>
        </div>
      </dl>
      <section class="flex flex-col gap-2 pt-3 border-t border-n-weak">
        <h4 class="m-0 text-xs font-medium text-n-slate-11">
          {{ $t('CONVERSATION_SIDEBAR.LEAF.INVOICES') }}
        </h4>
        <p
          v-if="!customer.open_invoices.length"
          class="m-0 text-xs text-n-slate-11"
        >
          {{ $t('CONVERSATION_SIDEBAR.LEAF.NO_INVOICES') }}
        </p>
        <div
          v-for="invoice in customer.open_invoices"
          :key="invoice.id"
          class="flex flex-col gap-2 border-b border-n-weak last:border-b-0"
        >
          <button
            type="button"
            class="flex w-full items-start justify-between gap-3 text-start"
            @click="toggleInvoice(invoice.id)"
          >
            <span class="flex flex-col gap-0.5 min-w-0">
              <span class="font-medium truncate">
                {{ invoice.description }}
              </span>
              <span class="text-xs text-n-slate-11">
                {{
                  $t('CONVERSATION_SIDEBAR.LEAF.DUE_ON', {
                    date: formatDueOn(invoice.due_on),
                  })
                }}
              </span>
            </span>
            <span class="shrink-0 font-medium tabular-nums">
              {{ formatAmount(invoice.amount_cents) }}
            </span>
          </button>
          <div
            v-if="selectedInvoiceId === invoice.id"
            class="flex flex-wrap gap-2"
          >
            <Button
              faded
              slate
              sm
              :label="$t('CONVERSATION_SIDEBAR.LEAF.PIX')"
              :is-loading="payingMethod === 'pix'"
              :disabled="busy"
              @click="sendPayment(invoice, 'pix')"
            />
            <Button
              faded
              slate
              sm
              :label="$t('CONVERSATION_SIDEBAR.LEAF.BOLETO')"
              :is-loading="payingMethod === 'boleto'"
              :disabled="busy"
              @click="sendPayment(invoice, 'boleto')"
            />
            <Button
              faded
              slate
              sm
              :label="$t('CONVERSATION_SIDEBAR.LEAF.CARD')"
              :is-loading="payingMethod === 'card'"
              :disabled="busy"
              @click="sendPayment(invoice, 'card')"
            />
          </div>
        </div>
      </section>
      <Button
        v-if="canUnblock"
        faded
        ruby
        sm
        class="w-full"
        :label="$t('CONVERSATION_SIDEBAR.LEAF.UNBLOCK')"
        :is-loading="unblocking"
        :disabled="busy"
        @click="unblockConnection"
      />
      <p v-if="actionError" role="alert" class="m-0 text-n-ruby-11">
        {{ actionError }}
      </p>
    </template>
  </div>
</template>
