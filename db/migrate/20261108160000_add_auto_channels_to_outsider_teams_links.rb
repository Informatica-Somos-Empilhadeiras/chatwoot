# OUTSIDER: área Teams. Só acrescenta colunas na tabela do próprio módulo (outsider_teams_links), nada do Chatwoot.
#   all_channels: todos os canais das equipes da pessoa entram sozinhos (inclusive os criados depois)
#   hidden_channels: canais que a pessoa desmarcou nesse modo [{ team_id, channel_id }]
#   history_at: quando as mensagens antigas dos chats foram trazidas
#   history_channels: canais cujas mensagens antigas já foram trazidas ["team_id|channel_id"]
class AddAutoChannelsToOutsiderTeamsLinks < ActiveRecord::Migration[7.1]
  def change
    add_column :outsider_teams_links, :all_channels, :boolean, null: false, default: true
    add_column :outsider_teams_links, :hidden_channels, :jsonb, null: false, default: []
    add_column :outsider_teams_links, :history_at, :datetime
    add_column :outsider_teams_links, :history_channels, :jsonb, null: false, default: []
  end
end
