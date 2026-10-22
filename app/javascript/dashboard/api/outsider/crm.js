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

  getReport(params) {
    return axios.get(`${this.url}/reports`, { params });
  }

  // seção Propostas da aba Relatórios (Entrega 18)
  getProposalReport(params) {
    return axios.get(`${this.url}/proposal_reports`, { params });
  }

  // automação "negócio parado" e regras com gatilho de tempo: roda a verificação na hora (só administrador)
  checkStalled() {
    return axios.post(`${this.url}/automations/stalled`);
  }

  // regras "quando acontecer X, faça Y" (só administrador)
  getAutomationRules() {
    return axios.get(`${this.url}/automation_rules`);
  }

  createAutomationRule(automationRule) {
    return axios.post(`${this.url}/automation_rules`, {
      automation_rule: automationRule,
    });
  }

  updateAutomationRule(id, automationRule) {
    return axios.patch(`${this.url}/automation_rules/${id}`, {
      automation_rule: automationRule,
    });
  }

  deleteAutomationRule(id) {
    return axios.delete(`${this.url}/automation_rules/${id}`);
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

  getUnownedCount(params = {}) {
    return axios.get(`${this.url}/opportunities/unowned`, { params });
  }

  claimOpportunity(id) {
    return axios.post(`${this.url}/opportunities/${id}/claim`);
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

  getForwardOptions(opportunityId) {
    return axios.get(`${this.url}/opportunities/${opportunityId}/forward`);
  }

  // to_business_unit_id, pipeline_id, owner_id, reason_id, notes, complete_tasks,
  // create_task, assign_conversation
  forwardOpportunity(opportunityId, forward) {
    return axios.post(`${this.url}/opportunities/${opportunityId}/forward`, {
      forward,
    });
  }

  // aba Metas: vendido, meta e comissão do mês (AAAA-MM)
  // only = 'me': só os números da própria pessoa (resumo da tela principal)
  getPerformance(month, only) {
    return axios.get(`${this.url}/performance`, { params: { month, only } });
  }

  // metas e comissão (só administrador)
  getGoals(month) {
    return axios.get(`${this.url}/goals`, { params: { month } });
  }

  updateGoals(month, units, users) {
    return axios.put(`${this.url}/goals`, { month, units, users });
  }

  getCommission() {
    return axios.get(`${this.url}/commission`);
  }

  updateCommission(generalBp, rules) {
    return axios.put(`${this.url}/commission`, {
      general_bp: generalBp,
      rules,
    });
  }

  getReceivedForwards() {
    return axios.get(`${this.url}/received_forwards`);
  }

  markReceivedForwards(opportunityIds, opened) {
    return axios.post(`${this.url}/received_forwards/mark`, {
      opportunity_ids: opportunityIds,
      opened,
    });
  }

  getContactHistory(contactId) {
    return axios.get(`${this.url}/contacts/${contactId}/history`);
  }

  // quem tem o CRM na conta (Configurações > Acesso, só administrador)
  getAgentAccesses() {
    return axios.get(`${this.url}/agent_accesses`);
  }

  updateAgentAccess(userId, enabled) {
    return axios.patch(`${this.url}/agent_accesses/${userId}`, { enabled });
  }

  // ---------- propostas (Entrega 14) ----------

  // catálogo de máquinas e acessórios; params: q, kind (machine|accessory), all (inativos também)
  getProducts(params) {
    return axios.get(`${this.url}/products`, { params });
  }

  createProduct(product) {
    return axios.post(`${this.url}/products`, { product });
  }

  updateProduct(id, product) {
    return axios.patch(`${this.url}/products/${id}`, { product });
  }

  deleteProduct(id) {
    return axios.delete(`${this.url}/products/${id}`);
  }

  uploadProductImage(id, file) {
    const data = new FormData();
    data.append('image', file);
    return axios.put(`${this.url}/products/${id}/image`, data);
  }

  removeProductImage(id) {
    return axios.delete(`${this.url}/products/${id}/image`);
  }

  // params: q, status (draft|sent|accepted|rejected|canceled|expired), kind, owner_id, contact_id,
  // opportunity_id, from, to, sort (recent|number|value), page
  getProposals(params) {
    return axios.get(`${this.url}/proposals`, { params });
  }

  getProposal(id) {
    return axios.get(`${this.url}/proposals/${id}`);
  }

  // dados com que a proposta nova abre: contact_id, opportunity_id, kind
  getProposalPrefill(params) {
    return axios.get(`${this.url}/proposals/prefill`, { params });
  }

  createProposal(proposal) {
    return axios.post(`${this.url}/proposals`, { proposal });
  }

  updateProposal(id, proposal) {
    return axios.patch(`${this.url}/proposals/${id}`, { proposal });
  }

  updateProposalStatus(id, status) {
    return axios.patch(`${this.url}/proposals/${id}/status`, { status });
  }

  deleteProposal(id) {
    return axios.delete(`${this.url}/proposals/${id}`);
  }

  // PDF montado na hora, como arquivo (blob) para mostrar ou baixar
  getProposalPdf(id) {
    return axios.get(`${this.url}/proposals/${id}/pdf`, {
      responseType: 'blob',
    });
  }

  // Envio ao cliente: contatos (ou a busca, com q), caixas, textos padrão e variáveis
  getProposalSendOptions(id, params = {}) {
    return axios.get(`${this.url}/proposals/${id}/sends/new`, { params });
  }

  // { channel, contact_id, inbox_id, message, subject }; devolve a proposta com o histórico
  sendProposal(id, payload) {
    return axios.post(`${this.url}/proposals/${id}/sends`, payload);
  }

  getProposalTemplates() {
    return axios.get(`${this.url}/proposal_templates`);
  }

  updateProposalTemplate(id, proposalTemplate) {
    return axios.patch(`${this.url}/proposal_templates/${id}`, {
      proposal_template: proposalTemplate,
    });
  }

  // slot: header | footer (papel timbrado)
  uploadProposalTemplateImage(id, slot, file) {
    const data = new FormData();
    data.append('image', file);
    return axios.put(
      `${this.url}/proposal_templates/${id}/images/${slot}`,
      data
    );
  }

  removeProposalTemplateImage(id, slot) {
    return axios.delete(`${this.url}/proposal_templates/${id}/images/${slot}`);
  }

  // { name, kind, source_id }: em branco (textos padrão do tipo) ou cópia de outro modelo
  createProposalTemplate(payload) {
    return axios.post(`${this.url}/proposal_templates`, payload);
  }

  deleteProposalTemplate(id) {
    return axios.delete(`${this.url}/proposal_templates/${id}`);
  }

  // PDF de exemplo com o que está no editor, sem salvar
  previewProposalTemplate(id, proposalTemplate) {
    return axios.post(
      `${this.url}/proposal_templates/${id}/preview`,
      { proposal_template: proposalTemplate },
      { responseType: 'blob' }
    );
  }

  // imagem de um elemento solto do papel timbrado; devolve { id, url }
  uploadProposalTemplateLayoutImage(id, file) {
    const data = new FormData();
    data.append('image', file);
    return axios.post(
      `${this.url}/proposal_templates/${id}/layout_images`,
      data
    );
  }

  // slot: header | footer (papel timbrado que vem com o CRM)
  getProposalTemplateDefaultImage(slot) {
    return axios.get(`${this.url}/proposal_templates/default_images/${slot}`, {
      responseType: 'blob',
    });
  }

  // Configurações > Propostas (só administrador)
  getProposalSettings() {
    return axios.get(`${this.url}/proposal_settings`);
  }

  // values: next_number, win_deal_on_accept, send_message, email_subject (só o que mudar)
  updateProposalGeneral(values) {
    return axios.patch(`${this.url}/proposal_settings/general`, values);
  }

  // unitId vazio: dados padrão da empresa
  updateProposalCompany(company, unitId) {
    return axios.patch(`${this.url}/proposal_settings/company`, {
      company,
      unit_id: unitId || undefined,
    });
  }

  // access: { view: own|users|all, user_ids, catalog }
  updateProposalAccess(userId, access) {
    return axios.patch(`${this.url}/proposal_settings/access/${userId}`, {
      access,
    });
  }

  updateProposalSignatureOf(userId, signature) {
    return axios.patch(`${this.url}/proposal_settings/signatures/${userId}`, {
      signature,
    });
  }

  // a própria assinatura (cargo e telefone que saem na proposta)
  getMyProposalSignature() {
    return axios.get(`${this.url}/proposal_signature`);
  }

  updateMyProposalSignature(signature) {
    return axios.patch(`${this.url}/proposal_signature`, { signature });
  }
}

export default new CrmAPI();
