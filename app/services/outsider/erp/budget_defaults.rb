# OUTSIDER: um rascunho de orçamento novo já preenchido, para o agente só escolher as peças: o cliente vem do vínculo
# do contato com o ERP (Outsider::Erp::ContactLink), o "A/C" é o nome do contato, o vendedor pré-preenche com o código do ERP do agente
# (editável; sem vínculo do agente, vai o último que a pessoa escolheu) e as condições são o padrão das
# Configurações. "Copiar" usa o mesmo caminho com o cliente, os itens e as
# condições de outro orçamento (Outsider::Erp::BudgetCopy).
class Outsider::Erp::BudgetDefaults
  class Invalid < StandardError; end

  def initialize(account, user)
    @account = account
    @user = user
    @settings = Outsider::Erp::Settings.new(account)
  end

  # copy: { 'empresa', 'codigo', 'nome', 'terms', 'items' } de outro orçamento (Outsider::Erp::BudgetCopy); o vendedor e
  # o A/C continuam sendo de quem abre e deste contato
  def build(contact:, conversation_id: nil, opportunity_id: nil, copy: nil)
    link = copy ? copy.slice('empresa', 'codigo', 'nome') : customer_link(contact)
    budget = Outsider::Erp::Budget.create!(
      account: @account, user: @user, contact: contact, conversation_id: Outsider::Erp::Budget.conversation_id_for(contact, conversation_id),
      opportunity_id: opportunity(contact, opportunity_id), status: :draft,
      company: link['empresa'], customer_code: link['codigo'], customer_name: link['nome'], terms: terms(contact), items: []
    )
    return budget unless copy

    # o que veio de outro orçamento passa pela mesma limpeza da tela
    Outsider::Erp::BudgetForm.new(budget, @settings).apply('terms' => copy['terms'].to_h.except('vendedor', 'contato'), 'items' => copy['items'])
  end

  private

  # o primeiro vínculo do contato; sem vínculo, a primeira unidade sem cliente (a tela pede o cliente antes de gravar)
  def customer_link(contact)
    link = contact && Outsider::Erp::ContactLink.new(contact).links.find { |row| @settings.companies.include?(row['empresa']) }
    link || { 'empresa' => @settings.companies.first.presence || raise(Invalid, 'no_companies') }
  end

  def terms(contact)
    data = @settings.data
    {
      'forma_pagto' => data['quote_forma_pagto'].to_i.positive? ? data['quote_forma_pagto'].to_i : nil,
      'genero' => Outsider::Erp::BudgetForm::GENERO, 'tipo_frete' => data['quote_tipo_frete'].to_i,
      'vendedor' => seller_code, 'contato' => contact&.name.to_s.first(50),
      'prazo_entrega' => data['quote_prazo_entrega'], 'validade' => data['quote_validade'], 'garantia' => data['quote_garantia']
    }.compact
  end

  # vendedor pré-preenchido com o código do ERP do agente (user_erp_ids), editável na tela; sem vínculo do agente,
  # cai no último vendedor que essa pessoa escolheu (e, na primeira vez, ela escolhe na lista)
  def seller_code
    mine = Integer(@settings.data['user_erp_ids'].to_h[@user&.id.to_s].to_s, exception: false)
    return mine if mine&.positive?

    last = Outsider::Erp::Budget.where(account_id: @account.id, user_id: @user&.id).where("terms ? 'vendedor'")
                                .order(updated_at: :desc).pick(Arel.sql("terms->>'vendedor'"))
    code = Integer(last.to_s, exception: false)
    code if code&.positive?
  end

  # só guarda o negócio do CRM se ele for deste contato
  def opportunity(contact, id)
    return if id.blank? || contact.nil?

    Outsider::Crm::Opportunity.where(account_id: @account.id, contact_id: contact.id).find_by(id: id)&.id
  end
end
