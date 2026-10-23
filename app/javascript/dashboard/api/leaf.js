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
}

export default new LeafAPI();
