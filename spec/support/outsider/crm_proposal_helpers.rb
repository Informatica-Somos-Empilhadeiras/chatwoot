# OUTSIDER: atalhos para montar produto e proposta nos specs das propostas do CRM.
module OutsiderCrmProposalHelpers
  def crm_product(account, **attrs)
    Outsider::Crm::Product.create!(
      { account: account, kind: :machine, name: 'Empilhadeira 3,5t', code: 'CPCD35', brand: 'HELI', sale_price_cents: 15_000_000,
        specs: [{ label: 'Capacidade de carga', value: '3500 kg', bold: true }, { label: 'Altura de elevação', value: '3000 mm' }],
        features: ['Motor diesel', 'Garfos de 1220 mm'] }.merge(attrs)
    )
  end

  def crm_proposal(account, owner:, kind: :sale, items: nil, **attrs)
    Outsider::Crm::ProposalTemplateDefaults.ensure!(account)
    contact = attrs.delete(:contact) || create(:contact, account: account)
    template = Outsider::Crm::ProposalTemplate.where(account_id: account.id, kind: kind).ordered.first
    proposal = Outsider::Crm::Proposal.new(
      { account: account, kind: kind, template: template, contact: contact, owner_id: owner.id, created_by_id: owner.id,
        title: 'Empilhadeira 3,5t', issued_on: Time.zone.today, customer: { 'company' => 'Cliente Exemplo Ltda' },
        conditions: template.conditions }.merge(attrs)
    )
    (items || [{ description: 'Empilhadeira', quantity: 1, unit_price_cents: 10_000_000 }]).each do |item|
      proposal.items.build({ account: account }.merge(item))
    end
    proposal.recalculate_total
    proposal.save!
    proposal
  end
end

RSpec.configure { |config| config.include OutsiderCrmProposalHelpers }
