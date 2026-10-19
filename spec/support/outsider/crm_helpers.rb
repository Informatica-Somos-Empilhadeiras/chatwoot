# OUTSIDER: atalhos para montar unidade, pipeline e oportunidade nos specs do CRM.
module OutsiderCrmHelpers
  def crm_unit(account, name: 'Locação')
    Outsider::Crm::BusinessUnit.create!(account: account, name: name)
  end

  def crm_pipeline(account, unit, name: 'Vendas')
    Outsider::Crm::Pipeline.create!(
      account: account, business_unit: unit, name: name,
      stages_attributes: [
        { name: 'Qualificação', position: 1, probability: 30 },
        { name: 'Proposta', position: 2, probability: 60 },
        { name: 'Ganho', position: 3, probability: 100, kind: :won },
        { name: 'Perdido', position: 4, probability: 0, kind: :lost }
      ]
    )
  end

  def crm_opportunity(account, unit, contact: create(:contact, account: account), **attrs)
    pipeline = attrs.delete(:pipeline) || crm_pipeline(account, unit)
    Outsider::Crm::Opportunity.create!(
      { account: account, business_unit: unit, pipeline: pipeline, stage: pipeline.first_open_stage, contact: contact,
        journey: Outsider::Crm::Journey.create!(account: account, contact: contact), title: 'Oportunidade' }.merge(attrs)
    )
  end
end

RSpec.configure { |config| config.include OutsiderCrmHelpers }
