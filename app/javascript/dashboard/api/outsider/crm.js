/* global axios */
// OUTSIDER: CRM de vendas (ver app/controllers/api/v1/accounts/outsider/crm/)
import ApiClient from '../ApiClient';

class CrmAPI extends ApiClient {
  constructor() {
    super('outsider/crm', { accountScoped: true });
  }

  getAccess() {
    return axios.get(`${this.url}/access`);
  }

  updateSettings(settings) {
    return axios.patch(`${this.url}/settings`, { settings });
  }

  getUnits() {
    return axios.get(`${this.url}/business_units`);
  }

  getUnit(id) {
    return axios.get(`${this.url}/business_units/${id}`);
  }

  createUnit(businessUnit) {
    return axios.post(`${this.url}/business_units`, {
      business_unit: businessUnit,
    });
  }

  updateUnit(id, businessUnit) {
    return axios.patch(`${this.url}/business_units/${id}`, {
      business_unit: businessUnit,
    });
  }

  deleteUnit(id) {
    return axios.delete(`${this.url}/business_units/${id}`);
  }

  addMember(unitId, userId, role) {
    return axios.post(`${this.url}/business_units/${unitId}/members`, {
      user_id: userId,
      role,
    });
  }

  updateMember(unitId, id, role) {
    return axios.patch(`${this.url}/business_units/${unitId}/members/${id}`, {
      role,
    });
  }

  removeMember(unitId, id) {
    return axios.delete(`${this.url}/business_units/${unitId}/members/${id}`);
  }

  getPipelines(params = {}) {
    return axios.get(`${this.url}/pipelines`, { params });
  }

  createPipeline(pipeline) {
    return axios.post(`${this.url}/pipelines`, { pipeline });
  }

  updatePipeline(id, pipeline) {
    return axios.patch(`${this.url}/pipelines/${id}`, { pipeline });
  }

  deletePipeline(id) {
    return axios.delete(`${this.url}/pipelines/${id}`);
  }

  getLostReasons() {
    return axios.get(`${this.url}/lost_reasons`);
  }

  createLostReason(lostReason) {
    return axios.post(`${this.url}/lost_reasons`, { lost_reason: lostReason });
  }

  updateLostReason(id, lostReason) {
    return axios.patch(`${this.url}/lost_reasons/${id}`, {
      lost_reason: lostReason,
    });
  }

  deleteLostReason(id) {
    return axios.delete(`${this.url}/lost_reasons/${id}`);
  }

  getCustomFields() {
    return axios.get(`${this.url}/custom_fields`);
  }

  createCustomField(customField) {
    return axios.post(`${this.url}/custom_fields`, {
      custom_field: customField,
    });
  }

  updateCustomField(id, customField) {
    return axios.patch(`${this.url}/custom_fields/${id}`, {
      custom_field: customField,
    });
  }

  deleteCustomField(id) {
    return axios.delete(`${this.url}/custom_fields/${id}`);
  }

  getOpportunities(params = {}) {
    return axios.get(`${this.url}/opportunities`, { params });
  }

  getOpportunity(id) {
    return axios.get(`${this.url}/opportunities/${id}`);
  }

  createOpportunity(opportunity) {
    return axios.post(`${this.url}/opportunities`, { opportunity });
  }

  updateOpportunity(id, opportunity) {
    return axios.patch(`${this.url}/opportunities/${id}`, { opportunity });
  }

  deleteOpportunity(id) {
    return axios.delete(`${this.url}/opportunities/${id}`);
  }

  getContactSummary(contactId, conversationId) {
    return axios.get(`${this.url}/contacts/${contactId}`, {
      params: conversationId ? { conversation_id: conversationId } : {},
    });
  }

  getContactSummaries(contactIds) {
    return axios.get(`${this.url}/contacts/summaries`, {
      params: { ids: contactIds.join(',') },
    });
  }

  getBoard(params) {
    return axios.get(`${this.url}/opportunities/board`, { params });
  }

  getSummary(params = {}) {
    return axios.get(`${this.url}/opportunities/summary`, { params });
  }

  exportOpportunities(params = {}) {
    return axios.get(`${this.url}/opportunities/export`, {
      params,
      responseType: 'blob',
    });
  }

  moveOpportunity(id, stageId, index) {
    return axios.patch(`${this.url}/opportunities/${id}/move`, {
      stage_id: stageId,
      index,
    });
  }

  getTasks(opportunityId) {
    return axios.get(`${this.url}/opportunities/${opportunityId}/tasks`);
  }

  createTask(opportunityId, task) {
    return axios.post(`${this.url}/opportunities/${opportunityId}/tasks`, {
      task,
    });
  }

  updateTask(opportunityId, id, task) {
    return axios.patch(
      `${this.url}/opportunities/${opportunityId}/tasks/${id}`,
      { task }
    );
  }

  deleteTask(opportunityId, id) {
    return axios.delete(
      `${this.url}/opportunities/${opportunityId}/tasks/${id}`
    );
  }

  // lista geral: assignee_id ('me', 'all' ou id), status ('pending' ou 'done'), due_before
  getTaskList(params = {}) {
    return axios.get(`${this.url}/tasks`, { params });
  }

  getActivities(opportunityId, params = {}) {
    return axios.get(`${this.url}/opportunities/${opportunityId}/activities`, {
      params,
    });
  }

  createNote(opportunityId, body, conversationDisplayId = null) {
    return axios.post(`${this.url}/opportunities/${opportunityId}/activities`, {
      activity: { body, conversation_display_id: conversationDisplayId },
    });
  }

  deleteActivity(opportunityId, id) {
    return axios.delete(
      `${this.url}/opportunities/${opportunityId}/activities/${id}`
    );
  }

  getAudits(opportunityId) {
    return axios.get(`${this.url}/opportunities/${opportunityId}/audits`);
  }
}

export default new CrmAPI();
