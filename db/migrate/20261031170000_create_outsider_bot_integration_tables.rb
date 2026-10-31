# OUTSIDER: integrações do bot (Configurações > Automação por bot > Conexões, Bases e Registro).
# outsider_bot_connections: sistemas externos (qualquer API ou o Nextcloud), com o login criptografado em secrets
# outsider_bot_datasets + outsider_bot_dataset_rows: planilhas enviadas, uma linha do banco por linha da planilha
#   (generation troca a planilha inteira de uma vez ao reenviar; folded é o texto sem acento para a busca)
# outsider_bot_logs: registro das chamadas a outros sistemas, apagado depois de 7 dias
# Só tabelas novas, sem chaves estrangeiras para as tabelas do Chatwoot.
class CreateOutsiderBotIntegrationTables < ActiveRecord::Migration[7.1]
  def change
    create_table :outsider_bot_connections do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.string :kind, null: false, default: 'http'
      t.string :base_url, null: false
      t.string :auth_type, null: false, default: 'none'
      t.jsonb :settings, null: false, default: {}
      t.text :secrets
      t.jsonb :headers, null: false, default: {}
      t.integer :timeout_seconds, null: false, default: 10
      t.boolean :allow_write, null: false, default: false
      t.bigint :created_by_id, :updated_by_id
      t.timestamps
    end
    add_index :outsider_bot_connections, [:account_id, :name], unique: true

    create_table :outsider_bot_datasets do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.jsonb :columns, null: false, default: []
      t.integer :rows_count, null: false, default: 0
      t.integer :generation, null: false, default: 0
      t.string :file_name
      t.bigint :created_by_id, :updated_by_id
      t.timestamps
    end
    add_index :outsider_bot_datasets, [:account_id, :name], unique: true

    # linhas da planilha: sem timestamps (são muitas e a planilha já guarda quando foi enviada)
    create_table :outsider_bot_dataset_rows do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.bigint :dataset_id, null: false
      t.integer :generation, null: false, default: 0
      t.integer :position, null: false
      t.jsonb :data, null: false, default: {}
      t.jsonb :folded, null: false, default: {}
    end
    add_index :outsider_bot_dataset_rows, [:dataset_id, :generation, :position], name: 'idx_obot_dataset_rows_order'
    add_index :outsider_bot_dataset_rows, :folded, using: :gin, opclass: :jsonb_path_ops, name: 'idx_obot_dataset_rows_folded'

    create_table :outsider_bot_logs do |t|
      t.bigint :account_id, null: false
      t.bigint :flow_id, :session_id, :conversation_id, :connection_id
      t.string :node_id
      t.string :kind, null: false
      t.string :status, null: false
      t.integer :http_status
      t.integer :duration_ms
      t.jsonb :detail, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :outsider_bot_logs, [:account_id, :id]
    add_index :outsider_bot_logs, :created_at
  end
end
