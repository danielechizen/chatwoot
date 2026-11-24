import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import LeafAPI from 'dashboard/api/leaf';
import LeafCustomerPanel from '../LeafCustomerPanel.vue';

vi.mock('dashboard/api/leaf', () => ({
  default: {
    customer: vi.fn(),
    invoices: vi.fn(),
  },
}));

const contact = {
  id: 3,
  custom_attributes: { plan: 'fibra', cpf_cnpj: '11144477735' },
};

const conversationFor = id => {
  if (Number(id) !== 7) return undefined;

  return {
    id: 7,
    meta: {
      sender: { id: 3, custom_attributes: contact.custom_attributes },
    },
  };
};

const store = createStore({
  getters: {
    getCurrentUser: () => ({ name: 'Ana' }),
    getConversationById: () => conversationFor,
  },
  modules: {
    contacts: {
      namespaced: true,
      getters: {
        getContact: () => id => (Number(id) === 3 ? contact : {}),
      },
    },
  },
});

const mountPanel = () =>
  mount(LeafCustomerPanel, {
    props: { conversationId: 7 },
    global: {
      plugins: [store],
      stubs: {
        Icon: true,
        Label: true,
        Select: true,
        Spinner: true,
      },
    },
  });

const reloadButton = wrapper =>
  wrapper.get('[aria-label="CONVERSATION_SIDEBAR.LEAF.RELOAD"]');

describe('LeafCustomerPanel', () => {
  beforeEach(() => {
    vi.spyOn(store, 'dispatch').mockResolvedValue({});
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('keeps the CPF/CNPJ editable and the reload visible when the lookup fails', async () => {
    LeafAPI.customer.mockRejectedValue({
      response: { data: { error: 'leaf_request_failed' } },
    });

    const wrapper = mountPanel();
    await flushPromises();

    expect(wrapper.text()).toContain('11144477735');
    expect(wrapper.text()).toContain('CONVERSATION_SIDEBAR.LEAF.ERROR');
    expect(reloadButton(wrapper).classes()).not.toContain('hidden');
  });

  it('shows the reload beside the customer name only on hover', async () => {
    LeafAPI.customer.mockResolvedValue({
      data: {
        found: true,
        customer_id: '1',
        customer: {
          name: 'Fibra Alfa',
          registration_status: 'ativo',
          contracts: [],
        },
      },
    });

    const wrapper = mountPanel();
    await flushPromises();

    const button = reloadButton(wrapper);

    expect(button.element.parentElement.textContent).toContain('Fibra Alfa');
    expect(button.classes()).toEqual(
      expect.arrayContaining(['hidden', 'group-hover:flex'])
    );
  });

  it('persists cpf_cnpj on the contact the same way other attributes do', async () => {
    LeafAPI.customer.mockRejectedValue({
      response: { data: { error: 'leaf_request_failed' } },
    });

    const wrapper = mountPanel();
    await flushPromises();

    const value = wrapper
      .findAll('span')
      .find(node => node.text() === '11144477735');
    await value.trigger('click');
    const input = wrapper.get('input');
    await input.setValue('529.982.247-25');
    await input.trigger('keydown.enter');
    await flushPromises();

    expect(store.dispatch).toHaveBeenCalledWith('contacts/update', {
      id: 3,
      customAttributes: {
        plan: 'fibra',
        cpf_cnpj: '529.982.247-25',
      },
    });
  });
});
