# OUTSIDER: Entrega 26 da telefonia.
# outsider_voice_ivr_flows: URA (atendimento automático por voz) desenhada como fluxograma; numbers diz por quais
#   números ela atende (vazio = todos os que não têm URA própria). Os áudios ficam no Active Storage.
# outsider_voice_monitors: registro de quem ouviu (modo fantasma) ou sussurrou numa ligação de outra pessoa.
# outsider_voice_calls.ivr_data: por onde o cliente passou na URA (opções e dígitos), mostrado a quem atende.
# outsider_teams_connections: robôs do Microsoft Teams ligados a uma caixa de entrada (API) do Chatwoot.
# Só tabelas e colunas novas, sem chaves estrangeiras para as tabelas do Chatwoot.
class CreateOutsiderVoiceIvrAndMonitors < ActiveRecord::Migration[7.1]
  def change
    create_table :outsider_voice_ivr_flows do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.boolean :active, null: false, default: false
      t.jsonb :graph, null: false, default: {}
      t.jsonb :numbers, null: false, default: []
      t.bigint :updated_by_id
      t.timestamps
    end
    add_index :outsider_voice_ivr_flows, :account_id

    create_table :outsider_voice_monitors do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.bigint :target_user_id, null: false
      t.bigint :call_id
      t.string :linkedid, null: false
      t.string :mode, null: false
      t.string :kind, null: false
      t.datetime :started_at, null: false
      t.datetime :opened_at
      t.datetime :ended_at
      t.timestamps
    end
    add_index :outsider_voice_monitors, :linkedid, unique: true
    add_index :outsider_voice_monitors, [:account_id, :started_at]

    add_column :outsider_voice_calls, :ivr_flow_id, :bigint
    add_column :outsider_voice_calls, :ivr_data, :jsonb, null: false, default: {}

    create_table :outsider_teams_connections do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false
      t.string :app_id, null: false
      t.string :tenant_id, null: false
      t.text :app_password_encrypted, null: false
      t.string :webhook_token, null: false
      t.datetime :last_activity_at
      t.timestamps
    end
    add_index :outsider_teams_connections, :inbox_id, unique: true
    add_index :outsider_teams_connections, :webhook_token, unique: true
  end
end
