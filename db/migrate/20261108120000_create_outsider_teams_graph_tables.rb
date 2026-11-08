# OUTSIDER: "Conectar meu Teams" (cada colaborador entra com a conta Microsoft dele; Microsoft Graph em nome dele).
# As conversas do Teams ficam em tabelas próprias, fora das conversas do Chatwoot: não entram nas listas, relatórios,
# automações, webhooks nem avisos do atendimento, e cada pessoa vê só as dela (área Teams do menu).
#   outsider_teams_graph_apps: o aplicativo da empresa no Microsoft Entra ID (um por conta), cadastrado uma vez pelo TI.
#   outsider_teams_links: o Teams de um colaborador (tokens cifrados, chats ligados ou não, canais escolhidos).
#   outsider_teams_subscriptions: os avisos de mensagem nova pedidos à Microsoft (um para os chats e um por canal).
#   outsider_teams_threads: um chat (1:1, grupo, reunião) ou um canal, na lista da área Teams.
#   outsider_teams_messages: as mensagens; no canal, reply_to_graph_id liga a resposta à publicação; quote = a mensagem
#     citada (chat); attachments = só nome, tamanho e endereço dos arquivos no OneDrive/SharePoint/Teams (nenhum arquivo
#     é gravado no Chatwoot: miniatura, imagem, visualização e download vêm da Microsoft na hora).
# Só tabelas novas, sem chaves estrangeiras para as tabelas do Chatwoot.
class CreateOutsiderTeamsGraphTables < ActiveRecord::Migration[7.1]
  def change
    create_table :outsider_teams_graph_apps do |t|
      t.bigint :account_id, null: false
      t.string :client_id, null: false
      t.string :tenant_id, null: false
      t.text :client_secret_encrypted, null: false
      t.datetime :consent_granted_at
      t.bigint :updated_by_id
      t.timestamps
    end
    add_index :outsider_teams_graph_apps, :account_id, unique: true

    create_table :outsider_teams_links do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.string :ms_user_id, null: false
      t.string :ms_tenant_id
      t.string :display_name
      t.string :email
      t.text :access_token_encrypted
      t.text :refresh_token_encrypted
      t.datetime :token_expires_at
      t.boolean :sync_chats, null: false, default: true
      t.jsonb :channels, null: false, default: []
      t.string :channel_view, null: false, default: 'conversa'
      t.string :status, null: false, default: 'active'
      t.string :last_error
      t.datetime :last_activity_at
      t.timestamps
    end
    add_index :outsider_teams_links, [:account_id, :user_id], unique: true
    add_index :outsider_teams_links, [:account_id, :ms_user_id], unique: true

    create_table :outsider_teams_subscriptions do |t|
      t.bigint :link_id, null: false
      t.string :kind, null: false
      t.string :team_id
      t.string :channel_id
      t.string :resource, null: false
      t.string :subscription_id
      t.string :client_state, null: false
      t.datetime :expires_at
      t.string :last_error
      t.timestamps
    end
    add_index :outsider_teams_subscriptions, :link_id
    add_index :outsider_teams_subscriptions, :subscription_id, unique: true

    create_table :outsider_teams_threads do |t|
      t.bigint :link_id, null: false
      t.string :kind, null: false
      t.string :chat_id
      t.string :chat_type
      t.string :team_id
      t.string :channel_id
      t.string :team_name
      t.string :title
      t.jsonb :members, null: false, default: []
      t.string :last_message_preview
      t.datetime :last_message_at
      t.integer :unread_count, null: false, default: 0
      t.integer :mention_count, null: false, default: 0
      t.datetime :last_read_at
      t.timestamps
    end
    add_index :outsider_teams_threads, [:link_id, :chat_id], unique: true, where: 'chat_id IS NOT NULL'
    add_index :outsider_teams_threads, [:link_id, :channel_id], unique: true, where: 'channel_id IS NOT NULL'
    add_index :outsider_teams_threads, [:link_id, :last_message_at]

    create_table :outsider_teams_messages do |t|
      t.bigint :thread_id, null: false
      t.string :graph_id
      t.string :reply_to_graph_id
      t.boolean :mine, null: false, default: false
      t.string :sender_name
      t.string :sender_ms_id
      t.string :subject
      t.text :content
      t.jsonb :attachments, null: false, default: []
      t.jsonb :quote
      t.boolean :mentions_me, null: false, default: false
      t.string :status, null: false, default: 'sent'
      t.string :error
      t.datetime :sent_at, null: false
      t.datetime :edited_at
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :outsider_teams_messages, [:thread_id, :graph_id], unique: true, where: 'graph_id IS NOT NULL'
    add_index :outsider_teams_messages, [:thread_id, :sent_at]
    add_index :outsider_teams_messages, [:thread_id, :reply_to_graph_id]
  end
end
