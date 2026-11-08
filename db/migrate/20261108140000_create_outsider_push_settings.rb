# OUTSIDER: o aviso novo no navegador e no celular (push com foto, "Nome · origem" e o texto). Uma linha por pessoa e
# conta: o que ela quer receber (tudo ligado quando não há linha), o nome de cada aparelho e se o navegador bloqueou.
# Os aparelhos em si continuam na tabela do Chatwoot (notification_subscriptions). Só cria esta tabela.
class CreateOutsiderPushSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :outsider_push_settings do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.jsonb :prefs, null: false, default: {}
      t.jsonb :devices, null: false, default: {}
      t.string :permission
      t.datetime :reminded_at
      t.timestamps
    end
    add_index :outsider_push_settings, [:account_id, :user_id], unique: true
    add_index :outsider_push_settings, :user_id
  end
end
