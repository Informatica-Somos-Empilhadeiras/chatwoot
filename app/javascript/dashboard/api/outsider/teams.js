/* global axios */
// OUTSIDER: Configurações > Microsoft Teams (ver app/controllers/api/v1/accounts/outsider/teams_connections_controller.rb)
import ApiClient from '../ApiClient';

class TeamsAPI extends ApiClient {
  constructor() {
    super('outsider/teams_connections', { accountScoped: true });
  }

  // confere app_id, segredo e locatário pedindo um token à Microsoft
  test(id) {
    return axios.post(`${this.url}/${id}/test`);
  }

  // pacote do aplicativo (.zip) para enviar no Teams
  manifest(id) {
    return axios.get(`${this.url}/${id}/manifest`, { responseType: 'blob' });
  }
}

export default new TeamsAPI();
