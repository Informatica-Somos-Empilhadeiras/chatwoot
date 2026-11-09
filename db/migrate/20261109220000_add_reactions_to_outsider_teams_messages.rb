# OUTSIDER: área Teams. Só acrescenta uma coluna na tabela do próprio módulo (outsider_teams_messages), nada do Chatwoot.
#   reactions: as reações da mensagem no Teams [{ type: "👍", user_id: id da pessoa na Microsoft, name: nome }]
class AddReactionsToOutsiderTeamsMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :outsider_teams_messages, :reactions, :jsonb, null: false, default: []
  end
end
