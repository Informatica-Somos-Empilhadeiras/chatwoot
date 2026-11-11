/* global axios */
// OUTSIDER: guarda a transcrição feita no navegador (ver app/controllers/api/v1/accounts/outsider/transcriptions_controller.rb)
import ApiClient from '../ApiClient';

class TranscriptionsAPI extends ApiClient {
  constructor() {
    super('outsider', { accountScoped: true });
  }

  // anexo de áudio/vídeo de uma mensagem do Chatwoot
  save(attachmentId, data) {
    return axios.post(`${this.url}/transcriptions`, {
      attachment_id: attachmentId,
      ...data,
    });
  }

  // endereço do áudio pela mesma origem (para a transcrição decodificar)
  audioUrl(attachmentId) {
    return `${this.url}/transcriptions/${attachmentId}/audio`;
  }

  remove(attachmentId) {
    return axios.delete(`${this.url}/transcriptions/${attachmentId}`);
  }

  // anexo de áudio de uma mensagem da área Teams
  saveTeams(messageId, index, data) {
    return axios.post(`${this.url}/transcriptions/teams/${messageId}`, {
      index,
      ...data,
    });
  }
}

export default new TranscriptionsAPI();
