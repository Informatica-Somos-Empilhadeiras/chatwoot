# OUTSIDER: automação por bot desenhada como fluxograma (Configurações > Automação por bot).
# outsider_bot_flows guarda o desenho (graph: blocos e ligações) e as caixas onde o fluxo roda;
# outsider_bot_sessions guarda onde cada conversa está no fluxo (uma ativa por conversa).
# Sem chaves estrangeiras para as tabelas do Chatwoot (apagar conversa ou caixa continua funcionando).
class CreateOutsiderBotTables < ActiveRecord::Migration[7.1]
  def change
    create_table :outsider_bot_flows do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.boolean :active, null: false, default: false
      t.jsonb :inbox_ids, null: false, default: []
      t.jsonb :graph, null: false, default: {}
      t.bigint :created_by_id, :updated_by_id
      t.timestamps
    end
    add_index :outsider_bot_flows, [:account_id, :active]

    create_table :outsider_bot_sessions do |t|
      t.bigint :account_id, :flow_id, :conversation_id, null: false
      t.string :node_id
      t.integer :status, null: false, default: 0
      t.jsonb :waiting, null: false, default: {}
      t.jsonb :variables, null: false, default: {}
      t.datetime :expires_at
      t.timestamps
    end
    add_index :outsider_bot_sessions, :conversation_id, unique: true, where: 'status = 0', name: 'idx_obot_sessions_one_active'
    add_index :outsider_bot_sessions, [:conversation_id, :created_at]
    add_index :outsider_bot_sessions, [:account_id, :flow_id, :created_at], name: 'idx_obot_sessions_on_flow'
  end
end
