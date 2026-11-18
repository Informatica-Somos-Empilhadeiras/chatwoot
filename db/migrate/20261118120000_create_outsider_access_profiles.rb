# OUTSIDER: perfis de acesso por tela (Administrador, Agente, Técnico e os criados pela conta) e o perfil de cada
# pessoa. Só tabelas novas: desfazer apaga as duas e todos voltam ao que o papel do Chatwoot permite.
class CreateOutsiderAccessProfiles < ActiveRecord::Migration[7.1]
  def change
    create_table :outsider_access_profiles do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.string :description
      # administrator, agent, technician (os três prontos) ou custom (criado pela conta)
      t.string :kind, null: false, default: 'custom'
      # perfil que novos usuários desse tipo recebem: agent ou technician
      t.string :default_for
      # { "tela" => "none" | "view" | "use" | "manage" }
      t.jsonb :permissions, null: false, default: {}
      t.references :created_by, index: false
      t.timestamps
    end
    add_index :outsider_access_profiles, [:account_id, :name], unique: true

    create_table :outsider_access_members do |t|
      t.references :account, null: false, index: false
      t.references :user, null: false, index: false
      t.references :profile, null: false, index: true
      t.timestamps
    end
    add_index :outsider_access_members, [:account_id, :user_id], unique: true
  end
end
