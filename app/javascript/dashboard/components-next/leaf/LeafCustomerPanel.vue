<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import LeafAPI from 'dashboard/api/leaf';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const PAYMENT_ACTIONS = [
  {
    method: 'pix',
    icon: 'i-lucide-qr-code',
    label: 'CONVERSATION_SIDEBAR.LEAF.PIX',
  },
  {
    method: 'boleto',
    icon: 'i-lucide-barcode',
    label: 'CONVERSATION_SIDEBAR.LEAF.BOLETO',
  },
  {
    method: 'card',
    icon: 'i-lucide-credit-card',
    label: 'CONVERSATION_SIDEBAR.LEAF.CARD',
  },
];

const { t } = useI18n();
const store = useStore();
const currentUser = useMapGetter('getCurrentUser');
const { run: runCustomer } = useAbortableRequest();
const {
  run: runInvoices,
  abort: abortInvoices,
  isPending: invoicesPending,
} = useAbortableRequest();

const lookup = ref(null);
const invoicesPayload = ref(null);
const loadError = ref('');
const invoicesError = ref('');
const actionError = ref('');
const selectedInvoiceId = ref('');
const selectedContract = ref('');
const payingMethod = ref('');
const unblocking = ref(false);
const disconnecting = ref(false);
const clearingMac = ref(false);

const customer = computed(() => lookup.value?.customer || null);
const connection = computed(() => customer.value?.connection || null);
const contracts = computed(() => customer.value?.contracts || []);
const openInvoices = computed(() => invoicesPayload.value?.open_invoices || []);
const paymentMethods = computed(
  () => invoicesPayload.value?.payment_methods || []
);
const visiblePaymentActions = computed(() =>
  PAYMENT_ACTIONS.filter(action => paymentMethods.value.includes(action.method))
);
const contractOptions = computed(() => [
  { value: '', label: t('CONVERSATION_SIDEBAR.LEAF.ALL_CONTRACTS') },
  ...contracts.value.map(contract => ({
    value: contract.number,
    label: contract.label,
  })),
]);
const showOnu = computed(
  () => connection.value?.technology === 'ftth' && !!connection.value?.onu
);
const showRx = computed(() => {
  const rx = connection.value?.onu?.rx_dbm;
  return rx !== undefined && rx !== null && rx !== '';
});
const showOnuError = computed(
  () =>
    connection.value?.onu?.status === 'offline' &&
    !!connection.value?.onu?.error
);
const canUnblock = computed(() => connection.value?.blocked === true);
const busy = computed(
  () =>
    unblocking.value ||
    disconnecting.value ||
    clearingMac.value ||
    payingMethod.value !== ''
);

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
    default:
      return t('CONVERSATION_SIDEBAR.LEAF.STATUS.UNKNOWN');
  }
};

const STATUS_COLORS = {
  online: 'teal',
  ativo: 'teal',
  offline: 'ruby',
  inativo: 'ruby',
  suspenso: 'amber',
};

const statusColor = status => STATUS_COLORS[status] || 'slate';

const connectionStatusColor = computed(() => {
  if (connection.value?.blocked) return 'amber';
  return statusColor(connection.value?.status);
});

const onuStatusColor = computed(() => {
  if (showOnuError.value) return 'ruby';
  return statusColor(connection.value?.onu?.status);
});

const registrationStatusColor = computed(() =>
  statusColor(customer.value?.registration_status)
);

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

const formatRx = value =>
  t('CONVERSATION_SIDEBAR.LEAF.RX_VALUE', {
    value: new Intl.NumberFormat(undefined, {
      maximumFractionDigits: 1,
      minimumFractionDigits: 1,
    }).format(value),
  });

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
    return { ...base, message: data.pix.copy_paste, files: [file], file };
  }

  if (data.method === 'boleto') {
    const file = fileFromBase64(
      data.boleto.pdf_base64,
      'boleto.pdf',
      'application/pdf'
    );
    return { ...base, message: '', files: [file], file };
  }

  return { ...base, message: data.card.payment_url };
};

const fetchInvoices = async () => {
  invoicesError.value = '';
  const contractNumber = selectedContract.value || undefined;
  try {
    const response = await runInvoices(signal =>
      LeafAPI.invoices(props.conversationId, contractNumber, signal)
    );
    if (response) invoicesPayload.value = response.data;
  } catch {
    invoicesError.value = t('CONVERSATION_SIDEBAR.LEAF.INVOICES_ERROR');
  }
};

const load = async () => {
  loadError.value = '';
  actionError.value = '';
  invoicesError.value = '';
  lookup.value = null;
  invoicesPayload.value = null;
  selectedInvoiceId.value = '';
  selectedContract.value = '';
  abortInvoices();
  try {
    const response = await runCustomer(signal =>
      LeafAPI.customer(props.conversationId, signal)
    );
    if (!response) return;

    lookup.value = response.data;
    if (response.data.found) await fetchInvoices();
  } catch (error) {
    loadError.value = messageFor(error);
  }
};

const refreshPanel = async () => {
  const response = await runCustomer(signal =>
    LeafAPI.customer(props.conversationId, signal)
  );
  if (response) lookup.value = response.data;
  if (lookup.value?.found) await fetchInvoices();
};

const onContractChange = value => {
  selectedContract.value = value ?? '';
  selectedInvoiceId.value = '';
  invoicesPayload.value = null;
  fetchInvoices();
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

const disconnectConnection = async () => {
  if (busy.value) return;

  actionError.value = '';
  disconnecting.value = true;
  try {
    await LeafAPI.disconnect(props.conversationId);
    await refreshPanel();
  } catch (error) {
    actionError.value = messageFor(error);
  } finally {
    disconnecting.value = false;
  }
};

const clearMac = async () => {
  if (busy.value) return;

  actionError.value = '';
  clearingMac.value = true;
  try {
    await LeafAPI.clearMac(props.conversationId);
    await refreshPanel();
  } catch (error) {
    actionError.value = messageFor(error);
  } finally {
    clearingMac.value = false;
  }
};

watch(() => props.conversationId, load, { immediate: true });
</script>

<template>
  <div class="flex flex-col gap-3 px-4 py-3 text-sm text-n-slate-12">
    <Spinner v-if="!lookup && !loadError" class="mx-auto" />
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
      <div class="flex items-center gap-2">
        <Icon icon="i-lucide-building-2 size-4 shrink-0 text-n-slate-11" />
        <span class="min-w-0 break-words">{{ customer.name }}</span>
      </div>
      <section class="flex flex-col gap-2">
        <h4 class="m-0 text-xs font-medium text-n-slate-11">
          {{ $t('CONVERSATION_SIDEBAR.LEAF.CONNECTION') }}
        </h4>
        <div v-if="connection.username" class="flex items-center gap-2">
          <Icon icon="i-lucide-user size-4 shrink-0 text-n-slate-11" />
          <span class="min-w-0 truncate">{{ connection.username }}</span>
        </div>
        <Label
          :label="statusLabel(connection.status)"
          :color="connectionStatusColor"
          compact
        />
        <div v-if="connection.last_log" class="flex items-start gap-2">
          <Icon icon="i-lucide-scroll-text size-4 shrink-0 text-n-slate-11" />
          <span class="min-w-0 break-words">{{ connection.last_log }}</span>
        </div>
      </section>
      <section v-if="showOnu" class="flex flex-col gap-2">
        <h4 class="m-0 text-xs font-medium text-n-slate-11">
          {{ $t('CONVERSATION_SIDEBAR.LEAF.ONU') }}
        </h4>
        <div class="flex items-center gap-2">
          <Icon icon="i-lucide-barcode size-4 shrink-0 text-n-slate-11" />
          <span class="min-w-0 truncate">{{ connection.onu.serial }}</span>
        </div>
        <Label
          :label="statusLabel(connection.onu.status)"
          :color="onuStatusColor"
          compact
        />
        <div v-if="showRx" class="flex items-center gap-2">
          <Icon icon="i-lucide-signal size-4 shrink-0 text-n-slate-11" />
          <span class="text-n-slate-11">
            {{ $t('CONVERSATION_SIDEBAR.LEAF.RX') }}
          </span>
          <span>{{ formatRx(connection.onu.rx_dbm) }}</span>
        </div>
        <div v-if="showOnuError" class="flex items-start gap-2">
          <Icon icon="i-lucide-triangle-alert size-4 shrink-0 text-n-ruby-11" />
          <span class="min-w-0 break-words">{{ connection.onu.error }}</span>
        </div>
      </section>
      <Label
        :label="statusLabel(customer.registration_status)"
        :color="registrationStatusColor"
        compact
      />
      <div class="flex items-center gap-2">
        <Button
          v-if="canUnblock"
          v-tooltip.top-end="$t('CONVERSATION_SIDEBAR.LEAF.UNBLOCK')"
          icon="i-lucide-lock-keyhole-open"
          slate
          faded
          sm
          :aria-label="$t('CONVERSATION_SIDEBAR.LEAF.UNBLOCK')"
          :is-loading="unblocking"
          :disabled="busy"
          @click="unblockConnection"
        />
        <Button
          v-tooltip.top-end="$t('CONVERSATION_SIDEBAR.LEAF.DISCONNECT')"
          icon="i-lucide-unplug"
          slate
          faded
          sm
          :aria-label="$t('CONVERSATION_SIDEBAR.LEAF.DISCONNECT')"
          :is-loading="disconnecting"
          :disabled="busy"
          @click="disconnectConnection"
        />
        <Button
          v-tooltip.top-end="$t('CONVERSATION_SIDEBAR.LEAF.CLEAR_MAC')"
          icon="i-lucide-eraser"
          slate
          faded
          sm
          :aria-label="$t('CONVERSATION_SIDEBAR.LEAF.CLEAR_MAC')"
          :is-loading="clearingMac"
          :disabled="busy"
          @click="clearMac"
        />
      </div>
      <section class="flex flex-col gap-2 pt-3 border-t border-n-weak">
        <h4 class="m-0 text-xs font-medium text-n-slate-11">
          {{ $t('CONVERSATION_SIDEBAR.LEAF.INVOICES') }}
        </h4>
        <Select
          v-if="contracts.length"
          :model-value="selectedContract"
          :options="contractOptions"
          :aria-label="$t('CONVERSATION_SIDEBAR.LEAF.CONTRACT')"
          @update:model-value="onContractChange"
        />
        <Spinner
          v-if="invoicesPending && !openInvoices.length"
          class="mx-auto"
        />
        <p
          v-else-if="invoicesError"
          role="alert"
          class="m-0 text-xs text-n-ruby-11"
        >
          {{ invoicesError }}
        </p>
        <p v-else-if="!openInvoices.length" class="m-0 text-xs text-n-slate-11">
          {{ $t('CONVERSATION_SIDEBAR.LEAF.NO_INVOICES') }}
        </p>
        <div
          v-for="invoice in openInvoices"
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
              v-for="action in visiblePaymentActions"
              :key="action.method"
              faded
              slate
              sm
              :icon="action.icon"
              :label="$t(action.label)"
              :is-loading="payingMethod === action.method"
              :disabled="busy"
              @click="sendPayment(invoice, action.method)"
            />
          </div>
        </div>
      </section>
      <p v-if="actionError" role="alert" class="m-0 text-n-ruby-11">
        {{ actionError }}
      </p>
    </template>
  </div>
</template>
