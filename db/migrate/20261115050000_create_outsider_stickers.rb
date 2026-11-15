# OUTSIDER: figurinhas (stickers) do WhatsApp. Cada atendente tem a própria coleção: as figurinhas que salvou
# das conversas ou subiu de imagens (arquivo webp 512x512 no ActiveStorage), favoritas e grupos (packs).
# Só cria tabelas novas.
class CreateOutsiderStickers < ActiveRecord::Migration[7.1]
  def change
    create_table :outsider_sticker_packs do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :outsider_sticker_packs, [:account_id, :user_id]

    create_table :outsider_stickers do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.bigint :pack_id
      t.string :emoji
      t.boolean :favorite, null: false, default: false
      t.boolean :animated, null: false, default: false
      t.integer :position, null: false, default: 0
      t.integer :uses_count, null: false, default: 0
      t.datetime :last_used_at
      t.string :digest, null: false
      t.string :source, null: false, default: 'upload'
      t.timestamps
    end
    add_index :outsider_stickers, [:account_id, :user_id]
    add_index :outsider_stickers, [:account_id, :user_id, :digest], unique: true, name: 'index_outsider_stickers_on_owner_and_digest'
    add_index :outsider_stickers, :pack_id
  end
end
