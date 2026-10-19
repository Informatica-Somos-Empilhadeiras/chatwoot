# OUTSIDER: CRM de vendas integrado ao Chatwoot. Tudo do CRM fica em Outsider::Crm (o Chatwoot já
# usa o namespace Crm para a integração LeadSquared) e em tabelas outsider_crm_*.
# Dados do Chatwoot (contatos, conversas, agentes) são só referenciados, nunca copiados.
module Outsider::Crm
  def self.table_name_prefix
    'outsider_crm_'
  end
end
