/* global axios */
// OUTSIDER: integração com o ERP Mais Prático (app/controllers/api/v1/accounts/outsider/erp/)
import ApiClient from '../ApiClient';

class ErpAPI extends ApiClient {
  constructor() {
    super('outsider/erp', { accountScoped: true });
  }

  status() {
    return axios.get(`${this.url}/status`);
  }

  settings() {
    return axios.get(`${this.url}/settings`);
  }

  saveSettings(settings) {
    return axios.patch(`${this.url}/settings`, { settings });
  }

  test() {
    return axios.post(`${this.url}/settings/test`);
  }

  contactOrders(contactId) {
    return axios.get(`${this.url}/service_orders`, {
      params: { contact_id: contactId },
    });
  }

  search(q) {
    return axios.get(`${this.url}/service_orders`, { params: { q } });
  }

  board(params) {
    return axios.get(`${this.url}/service_orders/board`, { params });
  }

  // relatório da OS com as fotos do checklist (PDF montado no servidor)
  serviceOrderReport(company, code) {
    return axios.get(`${this.url}/service_orders/report`, {
      params: { company, code },
      responseType: 'blob',
    });
  }

  // envio do relatório da OS ao cliente (como o do orçamento): textos, arquivo e para quem/por onde
  serviceOrderDelivery(params) {
    return axios.get(`${this.url}/service_orders/delivery`, { params });
  }

  serviceOrderContacts(q) {
    return axios.get(`${this.url}/service_orders/contacts`, { params: { q } });
  }

  deliverServiceOrder(data) {
    return axios.post(`${this.url}/service_orders/deliver`, data);
  }

  // agendar a OS nas agendas conectadas (Microsoft/Google) e avisar por WhatsApp
  orderSchedule(params) {
    return axios.get(`${this.url}/service_orders/schedule`, { params });
  }

  createOrderSchedule(data) {
    return axios.post(`${this.url}/service_orders/schedule`, data);
  }

  cancelOrderSchedule(id) {
    return axios.delete(`${this.url}/service_orders/schedule/${id}`);
  }

  // só um texto pelo WhatsApp sobre a OS (até 5 contatos)
  orderMessage(data) {
    return axios.post(`${this.url}/service_orders/message`, data);
  }

  // contatos (e-mail/WhatsApp) e colegas (e-mail) para convidar
  orderPeople(q) {
    return axios.get(`${this.url}/service_orders/people`, { params: { q } });
  }

  setSubstatus(data) {
    return axios.put(`${this.url}/service_orders/substatus`, data);
  }

  setField(data) {
    return axios.put(`${this.url}/service_orders/field`, data);
  }

  setStatus(data) {
    return axios.put(`${this.url}/service_orders/status`, data);
  }

  setAttendanceType(data) {
    return axios.put(`${this.url}/service_orders/attendance_type`, data);
  }

  setTechnician(data) {
    return axios.put(`${this.url}/service_orders/technician`, data);
  }

  // listas de apoio (situações, técnicos, tipos de atendimento) para os seletores da edição da OS
  lists() {
    return axios.get(`${this.url}/lists`);
  }

  // lista de peças e serviços do ERP numa unidade (abre pronta; q filtra por código ou nome)
  catalog(company, q) {
    return axios.get(`${this.url}/catalog`, { params: { company, q } });
  }

  // descrição técnica de um produto (aberta só quando pedida)
  technical(company, code) {
    return axios.get(`${this.url}/catalog/technical`, {
      params: { company, code },
    });
  }

  // pedido de venda: técnico e OS informados no chat (só no Chatwoot, para o relatório dos técnicos)
  saleAttribution(company, number) {
    return axios.get(
      `${this.url}/records/sales/${company}/${number}/attribution`
    );
  }

  previewSaleAttribution(company, number, os) {
    return axios.get(
      `${this.url}/records/sales/${company}/${number}/attribution/preview`,
      { params: { os } }
    );
  }

  // lines: [{ os, parte }]; approval: { code, password } (senha comercial)
  saveSaleAttribution(company, number, data) {
    return axios.put(
      `${this.url}/records/sales/${company}/${number}/attribution`,
      data
    );
  }

  removeSaleAttribution(company, number) {
    return axios.delete(
      `${this.url}/records/sales/${company}/${number}/attribution`
    );
  }

  // aba Produtos: o produto inteiro, com a lista das fotos (só leitura)
  product(company, code) {
    return axios.get(`${this.url}/catalog/${code}`, { params: { company } });
  }

  // só a lista das fotos de um produto (botão de fotos do orçamento)
  productPhotos(company, code) {
    return axios.get(`${this.url}/catalog/${code}/photos`, {
      params: { company },
    });
  }

  // quantas fotos têm os produtos já escolhidos no orçamento ({ counts: { 1022: 3 } })
  productPhotoCounts(company, codes) {
    return axios.get(`${this.url}/catalog/photo_counts`, {
      params: { company, codes: codes.join(',') },
    });
  }

  // a imagem em si (vem do Nextcloud); em blob porque o <img> não leva a autenticação da API
  productPhoto(company, code, id) {
    return axios.get(`${this.url}/catalog/${code}/photos/${id}`, {
      params: { company },
      responseType: 'blob',
    });
  }

  // a primeira foto em miniatura (JPG pequeno), para a lista mostrar a foto no lugar do ícone
  productThumbnail(company, code) {
    return axios.get(`${this.url}/catalog/${code}/thumbnail`, {
      params: { company },
      responseType: 'blob',
    });
  }

  // manda a foto ao cliente numa conversa que já existe (conversation_id ou contact_id)
  sendProductPhoto(company, code, id, data) {
    return axios.post(`${this.url}/catalog/${code}/photos/${id}/send`, {
      company,
      ...data,
    });
  }

  // orçamento de peças e serviços feito no chat (separado da proposta comercial do CRM)
  budgets(contactId) {
    return axios.get(`${this.url}/budgets`, {
      params: { contact_id: contactId },
    });
  }

  budget(id) {
    return axios.get(`${this.url}/budgets/${id}`);
  }

  // rascunho novo: contact_id, conversation_id (número da conversa), opportunity_id
  createBudget(data) {
    return axios.post(`${this.url}/budgets`, data);
  }

  saveBudget(id, budget) {
    return axios.patch(`${this.url}/budgets/${id}`, { budget });
  }

  deleteBudget(id) {
    return axios.delete(`${this.url}/budgets/${id}`);
  }

  submitBudget(id) {
    return axios.post(`${this.url}/budgets/${id}/submit`);
  }

  copyBudget(id, data) {
    return axios.post(`${this.url}/budgets/${id}/copy`, data);
  }

  // orçamento feito no próprio Mais Prático: vira registro para PDF, envio e cópia
  importBudget(data) {
    return axios.post(`${this.url}/budgets/import`, data);
  }

  // editar um orçamento já gravado (só em NEGOCIAÇÃO e fechado no Mais Prático): company, number, contact_id
  reviseBudget(data) {
    return axios.post(`${this.url}/budgets/revise`, data);
  }

  cancelRevision(id) {
    return axios.post(`${this.url}/budgets/${id}/cancel_revision`);
  }

  // seção ERP: listas com todo o histórico (kind: quotes, orders, sales) e o detalhe de um registro
  records(kind, params) {
    return axios.get(`${this.url}/records/${kind}`, { params });
  }

  record(kind, company, number) {
    return axios.get(`${this.url}/records/${kind}/${company}/${number}`);
  }

  // PDF montado na hora (prévia do rascunho ou o oficial do ERP), como arquivo
  // PDF de um orçamento do ERP direto da seção ERP (sem criar registro no chat)
  recordPdf(company, number) {
    return axios.get(`${this.url}/records/quotes/${company}/${number}/pdf`, {
      responseType: 'blob',
    });
  }

  // NF-e (invoices) e NFS-e (service_invoices): o PDF oficial da nota espelhado do Nextcloud
  invoiceDocument(kind, company, number) {
    return axios.get(
      `${this.url}/records/${kind}/${company}/${number}/document`,
      { responseType: 'blob' }
    );
  }

  // envio da nota (NF-e/NFS-e do Nextcloud) ao cliente, como o da OS: textos, arquivo e para quem/por onde
  invoiceDelivery(kind, company, number, params) {
    return axios.get(
      `${this.url}/records/${kind}/${company}/${number}/delivery`,
      { params }
    );
  }

  invoiceContacts(q) {
    return axios.get(`${this.url}/records/invoice_contacts`, {
      params: { q },
    });
  }

  deliverInvoice(kind, company, number, data) {
    return axios.post(
      `${this.url}/records/${kind}/${company}/${number}/deliver`,
      data
    );
  }

  budgetPdf(id) {
    return axios.get(`${this.url}/budgets/${id}/pdf`, { responseType: 'blob' });
  }

  budgetDelivery(id) {
    return axios.get(`${this.url}/budgets/${id}/delivery`);
  }

  budgetContacts(id, q) {
    return axios.get(`${this.url}/budgets/${id}/contacts`, { params: { q } });
  }

  deliverBudget(id, data) {
    return axios.post(`${this.url}/budgets/${id}/deliver`, data);
  }

  // desconto acima do limite: código e senha de quem libera no ERP (a senha não fica guardada em lugar nenhum)
  approveDiscount(id, data) {
    return axios.post(`${this.url}/budgets/${id}/approve_discount`, data);
  }

  // listas do formulário: formas de pagamento, vendedores, gêneros e fretes
  budgetOptions(company) {
    return axios.get(`${this.url}/budgets/options`, { params: { company } });
  }

  // clientes do ERP para vincular: sem q e com o contato, os parecidos com ele vêm primeiro
  customers(q, contactId) {
    return axios.get(`${this.url}/customers`, {
      params: { q, contact_id: contactId || undefined },
    });
  }

  // formas de pagamento do ERP (Configurações > Criar orçamento)
  paymentTerms() {
    return axios.get(`${this.url}/settings/payment_terms`);
  }

  // cadastrar cliente no ERP (pré-cadastro pela função do Mais Prático): vendedores da unidade e o do agente
  clientOptions(company) {
    return axios.get(`${this.url}/clients/options`, { params: { company } });
  }

  // já existe cliente com este CPF/CNPJ na unidade?
  clientLookup(company, documento) {
    return axios.get(`${this.url}/clients/lookup`, {
      params: { company, documento },
    });
  }

  // dados da empresa pelo CNPJ para preencher o cadastro (a mesma consulta das propostas)
  clientCompany(documento) {
    return axios.get(`${this.url}/clients/company`, { params: { documento } });
  }

  createClient(client, contactId) {
    return axios.post(`${this.url}/clients`, {
      client,
      contact_id: contactId || undefined,
    });
  }

  link(data) {
    return axios.post(`${this.url}/contact_link`, data);
  }

  unlink(data) {
    return axios.delete(`${this.url}/contact_link`, { data });
  }

  quotes(contactId) {
    return axios.get(`${this.url}/quotes`, {
      params: { contact_id: contactId },
    });
  }

  // Modelos de relatório (OS e orçamento): lista, estúdio, pré-visualização e qual modelo cada tipo de atendimento usa
  printTemplates() {
    return axios.get(`${this.url}/print_templates`);
  }

  printTemplate(id) {
    return axios.get(`${this.url}/print_templates/${id}`);
  }

  // { kind } para um modelo novo; { source_id } para copiar
  createPrintTemplate(data) {
    return axios.post(`${this.url}/print_templates`, data);
  }

  savePrintTemplate(id, data) {
    return axios.patch(`${this.url}/print_templates/${id}`, data);
  }

  deletePrintTemplate(id) {
    return axios.delete(`${this.url}/print_templates/${id}`);
  }

  restorePrintTemplate(id) {
    return axios.post(`${this.url}/print_templates/${id}/restore`);
  }

  uploadPrintImage(id, file) {
    const data = new FormData();
    data.append('image', file);
    return axios.post(`${this.url}/print_templates/${id}/upload_image`, data);
  }

  // PDF do modelo como está na tela; real = { company, number } para usar uma OS / orçamento de verdade
  printPreview(id, content, real = {}) {
    return axios.post(
      `${this.url}/print_templates/${id}/preview`,
      { content, ...real },
      { responseType: 'blob' }
    );
  }

  printSample(kind, real = {}) {
    return axios.get(`${this.url}/print_templates/sample`, {
      params: { kind, ...real },
    });
  }

  // foto do checklist de uma OS de verdade para a folha do estúdio (blob: a rota pede o login da API)
  printPhoto(company, number, ref) {
    return axios.get(`${this.url}/print_templates/photo`, {
      params: { company, number, ref },
      responseType: 'blob',
    });
  }

  savePrintBindings(kind, data) {
    return axios.put(`${this.url}/print_templates/bindings`, {
      kind,
      ...data,
    });
  }
}

export default new ErpAPI();
