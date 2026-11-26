/* global axios */
// OUTSIDER: "Conectar meu Teams" (login com a conta Microsoft de cada pessoa) e a área Teams do menu.
// Ver app/controllers/api/v1/accounts/outsider/teams_graph_controller.rb e teams_threads_controller.rb
import ApiClient from '../ApiClient';

class TeamsGraphAPI extends ApiClient {
  constructor() {
    super('outsider', { accountScoped: true });
  }

  // ---------- Configurações > Microsoft Teams ----------
  settings() {
    return axios.get(`${this.url}/teams_graph`);
  }

  saveApp(data) {
    return axios.put(`${this.url}/teams_graph/app`, data);
  }

  consentUrl() {
    return axios.post(`${this.url}/teams_graph/consent`);
  }

  authorizeUrl() {
    return axios.post(`${this.url}/teams_graph/authorize`);
  }

  // volta do login da Microsoft: { code, state } ou { error, error_description } ou { admin_consent, state }
  finish(data) {
    return axios.post(`${this.url}/teams_graph/finish`, data);
  }

  directory(refresh = false) {
    return axios.get(`${this.url}/teams_graph/teams`, {
      params: refresh ? { refresh: 1 } : {},
    });
  }

  updateMe(data) {
    return axios.patch(`${this.url}/teams_graph/me`, data);
  }

  disconnect() {
    return axios.delete(`${this.url}/teams_graph/me`);
  }

  disconnectPerson(linkId) {
    return axios.delete(`${this.url}/teams_graph/links/${linkId}`);
  }

  // ---------- área Teams ----------
  threads(kind) {
    return axios.get(`${this.url}/teams_threads`, { params: { kind } });
  }

  summary() {
    return axios.get(`${this.url}/teams_threads/summary`);
  }

  thread(id) {
    return axios.get(`${this.url}/teams_threads/${id}`);
  }

  // mode 'flat': canal em sequência (como um chat), com a publicação citada em cada resposta
  messages(id, { before, mode } = {}) {
    const params = {};
    if (before) params.before = before;
    if (mode) params.mode = mode;
    return axios.get(`${this.url}/teams_threads/${id}/messages`, { params });
  }

  // quoteId: mensagem citada; replyTo: publicação do canal em que a resposta entra
  send(id, { content, replyTo, subject, quoteId, files = [] }) {
    const data = new FormData();
    if (content) data.append('content', content);
    if (replyTo) data.append('reply_to_graph_id', replyTo);
    if (subject) data.append('subject', subject);
    if (quoteId) data.append('quote_id', quoteId);
    files.forEach(file => data.append('attachments[]', file));
    return axios.post(`${this.url}/teams_threads/${id}/messages`, data);
  }

  retry(id, messageId) {
    return axios.post(
      `${this.url}/teams_threads/${id}/messages/${messageId}/retry`
    );
  }

  // visualizar um arquivo do Teams: { kind: preview|image|none, view_url, download_url, edit_url, ... }
  preview(id, messageId, index) {
    return axios.post(
      `${this.url}/teams_threads/${id}/messages/${messageId}/attachments/${index}/preview`
    );
  }

  // quem dá para @mencionar: [{ id, name }]
  members(id) {
    return axios.get(`${this.url}/teams_threads/${id}/members`);
  }

  read(id) {
    return axios.post(`${this.url}/teams_threads/${id}/read`);
  }

  // reage (on true) ou tira a reação (on false) com o emoji; devolve a mensagem com as reações novas
  react(id, messageId, emoji, on) {
    return axios.post(
      `${this.url}/teams_threads/${id}/messages/${messageId}/react`,
      { emoji, on }
    );
  }

  // mensagens que citaram a pessoa neste chat/canal: [{ id, sent_at, sender_name }]
  mentions(id) {
    return axios.get(`${this.url}/teams_threads/${id}/mentions`);
  }

  // vários arquivos num .zip: items = [{ message_id, index }] -> { url, count }
  zip(id, items) {
    return axios.post(`${this.url}/teams_threads/${id}/zip`, { items });
  }

  // encaminhar mensagens deste chat/canal para até 5 chats/canais
  forward(id, { messageIds, targetIds, comment }) {
    return axios.post(`${this.url}/teams_threads/${id}/forward`, {
      message_ids: messageIds,
      target_ids: targetIds,
      comment,
    });
  }

  // quem está online: ids da Microsoft -> [{ id, availability, activity }]
  presence(ids) {
    return axios.post(`${this.url}/teams_threads/presence`, { ids });
  }

  // pessoas de todas as conversas, para convidar para uma reunião: [{ id, name, email }]
  people() {
    return axios.get(`${this.url}/teams_threads/people`);
  }

  // ---------- agenda ----------
  // eventos entre duas datas (ISO), no fuso informado
  calendar({ from, to, timeZone, calendarIds }) {
    return axios.get(`${this.url}/teams_calendar`, {
      params: { from, to, time_zone: timeZone, calendar_ids: calendarIds },
    });
  }

  // OUTSIDER: as agendas da pessoa e as compartilhadas com ela
  calendars() {
    return axios.get(`${this.url}/teams_calendar/calendars`);
  }

  // { subject, start, end, time_zone, attendees: [email], body, online: true/false, all_day }
  createEvent(data) {
    return axios.post(`${this.url}/teams_calendar`, data);
  }

  deleteEvent(id, calendarId) {
    return axios.delete(
      `${this.url}/teams_calendar/${encodeURIComponent(id)}`,
      {
        params: { calendar_id: calendarId },
      }
    );
  }
}

export default new TeamsGraphAPI();
