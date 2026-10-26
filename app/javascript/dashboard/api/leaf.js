/* global axios */
import ApiClient from './ApiClient';

class LeafAPI extends ApiClient {
  constructor() {
    super('integrations/leaf', { accountScoped: true });
  }

  customer(conversationId, contractNumber, signal) {
    const params = { conversation_id: String(conversationId) };
    if (contractNumber) params.contract_number = String(contractNumber);

    return axios.get(`${this.url}/customer`, { params, signal });
  }

  invoices(conversationId, contractNumber, signal) {
    const params = { conversation_id: String(conversationId) };
    if (contractNumber) params.contract_number = String(contractNumber);

    return axios.get(`${this.url}/invoices`, { params, signal });
  }

  payment(conversationId, invoiceId, method, contractNumber) {
    return axios.post(`${this.url}/payment`, {
      conversation_id: String(conversationId),
      contract_number: String(contractNumber),
      invoice_id: String(invoiceId),
      method,
    });
  }

  unblock(conversationId, contractNumber) {
    return axios.post(`${this.url}/unblock`, {
      conversation_id: String(conversationId),
      contract_number: String(contractNumber),
    });
  }

  disconnect(conversationId, contractNumber) {
    return axios.post(`${this.url}/disconnect`, {
      conversation_id: String(conversationId),
      contract_number: String(contractNumber),
    });
  }

  clearMac(conversationId, contractNumber) {
    return axios.post(`${this.url}/clear_mac`, {
      conversation_id: String(conversationId),
      contract_number: String(contractNumber),
    });
  }

  test() {
    return axios.post(`${this.url}/test`);
  }
}

export default new LeafAPI();
