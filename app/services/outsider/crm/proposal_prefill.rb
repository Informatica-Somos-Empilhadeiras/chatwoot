# OUTSIDER: dados com que uma proposta nova abre. A empresa do cliente vem da última proposta feita para o
# contato (que já tem CNPJ e endereço digitados) ou, na primeira, dos campos do contato do Chatwoot,
# inclusive atributos personalizados com nome de CNPJ, endereço etc. Nada é gravado de volta no contato.
class Outsider::Crm::ProposalPrefill
  # atributo personalizado do contato => campo da proposta (pela chave, sem acento e sem maiúscula)
  CUSTOM_KEYS = {
    'document' => /\A(cnpj|cpf|cpf_cnpj|cnpj_cpf|documento)\z/,
    'state_registration' => /\A(ie|inscricao_estadual|inscricao)\z/,
    'address' => /\A(endereco|logradouro|rua|address)\z/,
    'district' => /\A(bairro|district)\z/,
    'state' => /\A(estado|uf|state)\z/,
    'zip' => /\A(cep|zip|zipcode|zip_code)\z/,
    'city' => /\A(cidade|municipio|city)\z/
  }.freeze

  def initialize(account_user, contact:, opportunity: nil, kind: 'sale')
    @account_user = account_user
    @account = account_user.account
    @contact = contact
    @opportunity = opportunity
    @kind = Outsider::Crm::Proposal.kinds.key?(kind.to_s) ? kind.to_s : 'sale'
  end

  def as_json(*)
    template = Outsider::Crm::ProposalTemplate.where(account_id: @account.id, kind: @kind).active.ordered.first
    {
      kind: @kind, template_id: template&.id, title: '', contact_id: @contact.id, opportunity_id: @opportunity&.id,
      business_unit_id: @opportunity&.business_unit_id || first_unit_id, owner_id: @account_user.user_id,
      issued_on: Time.zone.today, valid_until: valid_until(template), customer: customer,
      conditions: template&.conditions || [], signer: signer
    }
  end

  def customer
    last = Outsider::Crm::Proposal.where(account_id: @account.id, contact_id: @contact.id).order(:id).last
    return last.customer.merge('attention' => last.customer['attention'].presence || @contact.name.to_s) if last

    from_contact
  end

  private

  def from_contact
    company = additional['company_name'].presence || company_name || @contact.name.to_s
    Outsider::Crm::Proposal::CUSTOMER_KEYS.index_with('').merge(
      'company' => company, 'city' => additional['city'].to_s, 'phone' => @contact.phone_number.to_s, 'email' => @contact.email.to_s,
      'attention' => company == @contact.name.to_s ? '' : @contact.name.to_s
    ).merge(custom_values)
  end

  def additional
    @additional ||= (@contact.additional_attributes || {}).stringify_keys
  end

  def company_name
    Company.find_by(id: @contact.company_id, account_id: @account.id)&.name if @contact.company_id
  end

  def custom_values
    (@contact.custom_attributes || {}).each_with_object({}) do |(key, value), found|
      field = custom_field(key)
      found[field] ||= value.to_s if field && value.present?
    end
  end

  def custom_field(key)
    name = I18n.transliterate(key.to_s).downcase
    CUSTOM_KEYS.find { |_field, pattern| pattern.match?(name) }&.first
  end

  def valid_until(template)
    days = template&.validity_days.to_i
    Time.zone.today + days if days.positive?
  end

  def first_unit_id
    Outsider::Crm::Access.new(@account_user).visible_unit_ids.first
  end

  def signer
    user = @account_user.user
    signature = Outsider::Crm::ProposalConfig.new(@account).signature(user.id)
    { 'name' => user.name.to_s, 'title' => signature['title'], 'phone' => signature['phone'], 'email' => user.email.to_s }
  end
end
