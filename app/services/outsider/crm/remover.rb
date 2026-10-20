# OUTSIDER: apagar unidade, pipeline, campo personalizado e negócio pelas telas do CRM.
# Apaga de verdade quando nada depende do item; senão recusa dizendo o que impede (Blocked), para a
# tela explicar: negócios na unidade ou no pipeline, regras de automação que apontam para eles,
# negócios com o campo preenchido, ou negócio encaminhado que ainda tem a cópia na outra unidade.
# Para limpar os testes de uma vez existe o bin/rails outsider_crm:limpar_negocios.
class Outsider::Crm::Remover
  class Blocked < StandardError
    attr_reader :reason, :details

    def initialize(reason, **details)
      @reason = reason
      @details = details
      super(reason)
    end
  end

  def initialize(account)
    @account = account
  end

  # Unidade sem negócios: sai com os membros e os pipelines (e as etapas deles)
  def unit(unit)
    block_if_opportunities(Outsider::Crm::Opportunity.where(business_unit_id: unit.id))
    pipeline_ids = unit.pipelines.ids
    block_if_rules { |conditions| conditions['business_unit_id'] == unit.id || pipeline_ids.include?(conditions['pipeline_id']) }
    ActiveRecord::Base.transaction do
      unit.pipelines.each(&:destroy!)
      unit.reload.destroy!
    end
  end

  def pipeline(pipeline)
    block_if_opportunities(pipeline.opportunities)
    block_if_rules { |conditions| conditions['pipeline_id'] == pipeline.id }
    pipeline.destroy!
  end

  def custom_field(field)
    count = Outsider::Crm::Opportunity.where(account_id: @account.id).where("COALESCE(custom_fields ->> ?, '') <> ''", field.key).count
    raise Blocked.new('has_values', count: count) if count.positive?

    field.destroy!
  end

  # Encaminhado: apaga-se a partir da ponta. A cópia na unidade de destino sai junto com o registro do
  # encaminhamento; depois disso a origem também pode sair. Tarefas e linha do tempo saem com o negócio.
  def opportunity(opportunity)
    target = opportunity.outgoing_forward&.to_opportunity
    raise Blocked.new('forwarded_out', code: target.code, unit: target.business_unit.name) if target

    journey = opportunity.journey
    ActiveRecord::Base.transaction do
      Outsider::Crm::Forward.where(to_opportunity_id: opportunity.id).destroy_all
      Outsider::Crm::Forward.where(from_opportunity_id: opportunity.id).destroy_all
      opportunity.reload.destroy!
      tidy(journey)
    end
  end

  private

  def block_if_opportunities(scope)
    count = scope.count
    raise Blocked.new('has_opportunities', count: count) if count.positive?
  end

  def block_if_rules
    names = Outsider::Crm::AutomationRules.new(@account).all.select { |rule| yield(rule['conditions'] || {}) }.pluck('name')
    raise Blocked.new('used_by_rules', names: names.join(', ')) if names.any?
  end

  # Jornada sem negócios some; com outros negócios, recalcula a situação
  def tidy(journey)
    if journey.opportunities.exists?
      journey.sync_status!
    elsif !journey.forwards.exists?
      journey.destroy!
    end
  end
end
