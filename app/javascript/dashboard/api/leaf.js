/* global axios */
import ApiClient from './ApiClient';

class LeafAPI extends ApiClient {
  constructor() {
    super('integrations/leaf', { accountScoped: true });
  }

  customer(conversationId, signal) {
    return axios.get(`${this.url}/customer`, {
      params: { conversation_id: String(conversationId) },
      signal,
    });
  }

  invoices(conversationId, contractNumber, signal) {
    const params = { conversation_id: String(conversationId) };
    if (contractNumber) params.contract_number = contractNumber;

    return axios.get(`${this.url}/invoices`, { params, signal });
  }

  payment(conversationId, invoiceId, method) {
    return axios.post(`${this.url}/payment`, {
      conversation_id: String(conversationId),
      invoice_id: invoiceId,
      method,
    });
  }

  unblock(conversationId) {
    return axios.post(`${this.url}/unblock`, {
      conversation_id: String(conversationId),
    });
  }

  disconnect(conversationId) {
    return axios.post(`${this.url}/disconnect`, {
      conversation_id: String(conversationId),
    });
  }

  clearMac(conversationId) {
    return axios.post(`${this.url}/clear_mac`, {
      conversation_id: String(conversationId),
    });
  }

  test() {
    return axios.post(`${this.url}/test`);
  }
}

export default new LeafAPI();
