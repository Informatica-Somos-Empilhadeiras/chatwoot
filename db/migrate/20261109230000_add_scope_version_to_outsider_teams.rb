# OUTSIDER: área Teams. Só colunas novas nas tabelas do próprio módulo, nada do Chatwoot.
#   outsider_teams_links.scope_version: versão das permissões com que a pessoa entrou (Outsider::Teams::Graph::Login::
#     SCOPE_VERSION); menor que a atual = "entre de novo para liberar as novidades" (o que já funcionava segue)
#   outsider_teams_graph_apps.consent_version: versão das permissões que o administrador aprovou pela empresa
#   outsider_teams_threads.members_at: quando a lista de pessoas da equipe do canal foi buscada por último
class AddScopeVersionToOutsiderTeams < ActiveRecord::Migration[7.1]
  def change
    add_column :outsider_teams_links, :scope_version, :integer, null: false, default: 1
    add_column :outsider_teams_graph_apps, :consent_version, :integer, null: false, default: 1
    add_column :outsider_teams_threads, :members_at, :datetime
  end
end
