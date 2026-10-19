# OUTSIDER: limpa os negócios de teste do CRM antes de liberar para a equipe. Só mexe nas
# tabelas outsider_crm_* (e no histórico de auditoria delas); nada do Chatwoot é apagado.
#   bin/rails outsider_crm:limpar_negocios CONFIRMAR=sim            # negócios, jornadas, tarefas, atividades
#   bin/rails outsider_crm:limpar_negocios CONFIRMAR=sim TUDO=sim   # também unidades, pipelines, motivos e campos
namespace :outsider_crm do
  desc 'Apaga os negócios do CRM (CONFIRMAR=sim; TUDO=sim apaga também a configuração)'
  task limpar_negocios: :environment do
    abort 'Nada foi apagado. Rode de novo com CONFIRMAR=sim.' unless ENV['CONFIRMAR'] == 'sim'

    crm = Outsider::Crm
    deals = [crm::Forward, crm::Activity, crm::Task, crm::Opportunity, crm::Journey]
    setup = [crm::BusinessUnitMember, crm::Stage, crm::Pipeline, crm::BusinessUnit, crm::LostReason, crm::CustomFieldDefinition]
    models = ENV['TUDO'] == 'sim' ? deals + setup : deals

    ActiveRecord::Base.transaction do
      Audited::Audit.where(auditable_type: models.map(&:name)).delete_all
      models.each { |model| puts "#{model.table_name}: #{model.delete_all} apagados" }
    end
  end
end
