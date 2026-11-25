# OUTSIDER: OS do ERP Mais Prático feita no chat: a Nova OS (rascunho com cliente, máquina, atendimento e peças) e a
# conversão de um orçamento do ERP em OS. O rascunho fica aqui até "Gravar no ERP"; depois guarda o número que a OS
# ganhou e o resultado de cada passo (conferência, cabeçalho, histórico, itens, orçamento fechado). Só cria a tabela
# (rollback remove). Ver Outsider::Erp::OrderDraft.
class CreateOutsiderErpOrderDrafts < ActiveRecord::Migration[7.1]
  def change
    create_table :outsider_erp_order_drafts do |t|
      t.bigint :account_id, null: false
      t.bigint :contact_id, :conversation_id, :user_id
      t.integer :kind, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.string :company, null: false
      t.integer :customer_code
      t.string :customer_name
      t.integer :quote_number
      t.jsonb :fields, null: false, default: {}
      t.jsonb :items, null: false, default: []
      t.integer :erp_number
      t.datetime :erp_created_at
      t.jsonb :erp_result, null: false, default: {}
      t.timestamps
    end
    add_index :outsider_erp_order_drafts, [:account_id, :contact_id]
    add_index :outsider_erp_order_drafts, [:account_id, :company, :quote_number], name: 'index_outsider_erp_order_drafts_on_quote'
    add_index :outsider_erp_order_drafts, [:account_id, :company, :erp_number],
              unique: true, where: 'erp_number IS NOT NULL', name: 'index_outsider_erp_order_drafts_on_erp_number'
  end
end
