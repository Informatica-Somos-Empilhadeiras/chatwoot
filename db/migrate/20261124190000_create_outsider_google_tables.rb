# OUTSIDER: bloco Google dos Aplicativos (Gmail, Agenda e Drive). Cada colaborador entra com a conta Google dele; os
# e-mails, eventos e arquivos são lidos do Google na hora e nada disso é gravado no Chatwoot.
#   outsider_google_apps: o aplicativo OAuth da empresa no Google Cloud (um por conta), cadastrado uma vez pelo TI.
#   outsider_google_links: a conta Google de um colaborador (tokens cifrados, permissões que ele aceitou) e o último
#     ponto do histórico do Gmail que o observador já viu (history_id), para avisar de e-mail novo a cada 5 minutos.
# Só tabelas novas, sem chaves estrangeiras para as tabelas do Chatwoot.
class CreateOutsiderGoogleTables < ActiveRecord::Migration[7.1]
  def change
    create_table :outsider_google_apps do |t|
      t.bigint :account_id, null: false
      t.string :client_id, null: false
      t.text :client_secret_encrypted, null: false
      t.bigint :updated_by_id
      t.timestamps
    end
    add_index :outsider_google_apps, :account_id, unique: true

    create_table :outsider_google_links do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.string :google_user_id, null: false
      t.string :email
      t.string :display_name
      t.text :access_token_encrypted
      t.text :refresh_token_encrypted
      t.datetime :token_expires_at
      t.text :scopes
      t.string :status, null: false, default: 'active'
      t.string :last_error
      t.string :history_id
      t.datetime :checked_at
      t.timestamps
    end
    add_index :outsider_google_links, [:account_id, :user_id], unique: true
    add_index :outsider_google_links, [:account_id, :google_user_id], unique: true
    add_index :outsider_google_links, :status
  end
end
