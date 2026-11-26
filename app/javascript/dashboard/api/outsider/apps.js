/* global axios */
// OUTSIDER: Aplicativos (blocos Microsoft e Google do menu). Tudo é espelho: o servidor pede à Microsoft/Google na hora
// e não guarda e-mail nem arquivo. Ver app/controllers/api/v1/accounts/outsider/apps/*.
import ApiClient from '../ApiClient';

class AppsAPI extends ApiClient {
  constructor() {
    super('outsider/apps', { accountScoped: true });
  }

  summary() {
    return axios.get(`${this.url}/summary`);
  }

  // ---------- e-mail (provider: microsoft | google) ----------
  mailFolders(provider) {
    return axios.get(`${this.url}/${provider}/mail/folders`);
  }

  // params: { folder, filter, q, cursor }
  mailMessages(provider, params) {
    return axios.get(`${this.url}/${provider}/mail/messages`, { params });
  }

  mailMessage(provider, id) {
    return axios.get(
      `${this.url}/${provider}/mail/messages/${encodeURIComponent(id)}`
    );
  }

  updateMail(provider, id, data) {
    return axios.patch(
      `${this.url}/${provider}/mail/messages/${encodeURIComponent(id)}`,
      data
    );
  }

  moveMail(provider, id, destination) {
    return axios.post(
      `${this.url}/${provider}/mail/messages/${encodeURIComponent(id)}/move`,
      { destination }
    );
  }

  // data: { mode, to, cc, bcc, subject, text, source_id, files: File[] }
  sendMail(provider, data) {
    const form = new FormData();
    Object.entries(data).forEach(([key, value]) => {
      if (key === 'files')
        (value || []).forEach(file => form.append('files[]', file));
      else if (Array.isArray(value))
        value.forEach(item => form.append(`${key}[]`, item));
      else if (value !== null && value !== undefined) form.append(key, value);
    });
    return axios.post(`${this.url}/${provider}/mail/messages`, form);
  }

  // ---------- arquivos ----------
  // params: { view, drive_id, folder_id, q, cursor }
  driveItems(provider, params) {
    return axios.get(`${this.url}/${provider}/drive/items`, { params });
  }

  driveItem(provider, item) {
    return axios.get(
      `${this.url}/${provider}/drive/items/${encodeURIComponent(item.id)}`,
      { params: { drive_id: item.drive_id } }
    );
  }

  drivePreview(provider, item) {
    return axios.get(
      `${this.url}/${provider}/drive/items/${encodeURIComponent(item.id)}/preview`,
      { params: { drive_id: item.drive_id } }
    );
  }

  driveDownload(provider, item) {
    return axios.get(
      `${this.url}/${provider}/drive/items/${encodeURIComponent(item.id)}/download`,
      { params: { drive_id: item.drive_id } }
    );
  }

  driveShare(provider, item, scope = 'organization') {
    return axios.post(
      `${this.url}/${provider}/drive/items/${encodeURIComponent(item.id)}/share`,
      { drive_id: item.drive_id, scope }
    );
  }

  driveDelete(provider, item) {
    return axios.delete(
      `${this.url}/${provider}/drive/items/${encodeURIComponent(item.id)}`,
      { params: { drive_id: item.drive_id } }
    );
  }

  driveFolder(provider, { driveId, parentId, name }) {
    return axios.post(`${this.url}/${provider}/drive/folders`, {
      drive_id: driveId,
      parent_id: parentId,
      name,
    });
  }

  driveUpload(provider, { driveId, parentId, file }, onUploadProgress) {
    const form = new FormData();
    if (driveId) form.append('drive_id', driveId);
    if (parentId) form.append('parent_id', parentId);
    form.append('file', file);
    return axios.post(`${this.url}/${provider}/drive/items`, form, {
      onUploadProgress,
    });
  }

  // ---------- Google: a conta de cada pessoa (Configurações > Google) e a agenda ----------
  googleAccount() {
    return axios.get(`${this.url}/google/account`);
  }

  saveGoogleApp(data) {
    return axios.put(`${this.url}/google/account/app`, data);
  }

  googleAuthorize() {
    return axios.post(`${this.url}/google/account/authorize`);
  }

  googleFinish(params) {
    return axios.post(`${this.url}/google/account/finish`, params);
  }

  googleDisconnect() {
    return axios.delete(`${this.url}/google/account`);
  }

  googleRemoveLink(id) {
    return axios.delete(`${this.url}/google/account/links/${id}`);
  }

  // OUTSIDER: as agendas que a pessoa vê no Google (a principal e as compartilhadas com ela)
  googleCalendars() {
    return axios.get(`${this.url}/google/calendar/calendars`);
  }

  googleEvents({ from, to, timeZone, calendarIds }) {
    return axios.get(`${this.url}/google/calendar/events`, {
      params: { from, to, time_zone: timeZone, calendar_ids: calendarIds },
    });
  }

  googleCreateEvent(data) {
    return axios.post(`${this.url}/google/calendar/events`, data);
  }

  googleDeleteEvent(id, calendarId) {
    return axios.delete(
      `${this.url}/google/calendar/events/${encodeURIComponent(id)}`,
      { params: { calendar_id: calendarId } }
    );
  }

  googlePeople() {
    return axios.get(`${this.url}/google/calendar/people`);
  }
}

export default new AppsAPI();
