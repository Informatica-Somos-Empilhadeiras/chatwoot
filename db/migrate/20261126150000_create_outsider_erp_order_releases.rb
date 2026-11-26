# OUTSIDER: "Liberar para separação" de uma OS do ERP feito pelo chat (Outsider::Erp::Orders::Releaser). O Mais Prático
# não guarda quem liberou; aqui fica quem foi, quando e quantos itens, para o painel e a linha do tempo da OS. Só cria a
# tabela (rollback remove).
class CreateOutsiderErpOrderReleases < ActiveRecord::Migration[7.1]
  def change
    create_table :outsider_erp_order_releases do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id
      t.string :company, null: false
      t.integer :order_number, null: false
      t.integer :items_count, null: false, default: 0
      t.timestamps
    end
    add_index :outsider_erp_order_releases, [:account_id, :company, :order_number], name: 'index_outsider_erp_order_releases_on_order'
  end
end
