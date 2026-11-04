/* global axios */
import ApiClient from './ApiClient';

class LeafAPI extends ApiClient {
  constructor() {
    super('integrations/leaf', { accountScoped: true });
  }

  customer(conversationId, contractNumber, customerId, signal) {
    const params = { conversation_id: String(conversationId) };
    if (contractNumber) params.contract_number = String(contractNumber);
    if (customerId) params.customer_id = String(customerId);

    return axios.get(`${this.url}/customer`, { params, signal });
  }

  invoices(conversationId, contractNumber, customerId, signal) {
    const params = { conversation_id: String(conversationId) };
    if (contractNumber) params.contract_number = String(contractNumber);
    if (customerId) params.customer_id = String(customerId);

    return axios.get(`${this.url}/invoices`, { params, signal });
  }

  payment(conversationId, invoiceId, method, contractNumber, customerId) {
    const payload = {
      conversation_id: String(conversationId),
      contract_number: String(contractNumber),
      invoice_id: String(invoiceId),
      method,
    };
    if (customerId) payload.customer_id = String(customerId);

    return axios.post(`${this.url}/payment`, payload);
  }

  unblock(conversationId, contractNumber, customerId) {
    const payload = {
      conversation_id: String(conversationId),
      contract_number: String(contractNumber),
    };
    if (customerId) payload.customer_id = String(customerId);

    return axios.post(`${this.url}/unblock`, payload);
  }

  disconnect(conversationId, contractNumber, customerId) {
    const payload = {
      conversation_id: String(conversationId),
      contract_number: String(contractNumber),
    };
    if (customerId) payload.customer_id = String(customerId);

    return axios.post(`${this.url}/disconnect`, payload);
  }

  clearMac(conversationId, contractNumber, customerId) {
    const payload = {
      conversation_id: String(conversationId),
      contract_number: String(contractNumber),
    };
    if (customerId) payload.customer_id = String(customerId);

    return axios.post(`${this.url}/clear_mac`, payload);
  }

  test(systemUrl, apiKey) {
    const payload = {};
    const url = (systemUrl || '').trim();
    const key = (apiKey || '').trim();
    if (url) payload.system_url = url;
    if (key) payload.api_key = key;

    return axios.post(`${this.url}/test`, payload);
  }
}

export default new LeafAPI();
