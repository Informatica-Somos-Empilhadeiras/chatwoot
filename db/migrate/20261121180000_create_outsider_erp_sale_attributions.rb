# OUTSIDER: técnico e OS de um pedido de venda do ERP, informados pelo vendedor no chat (o Mais Prático não tem esses
# campos no pedido). Fica só no Chatwoot, nunca vai para o ERP; é o que o relatório de desempenho dos técnicos usa.
# lines: [{ os, parte (%), tecnico_codigo, tecnico }]; approval: quem liberou com a senha comercial quando a OS
# não bateu com o pedido (código e nome do ERP, nunca a senha); history: cada alteração. Só cria a tabela.
class CreateOutsiderErpSaleAttributions < ActiveRecord::Migration[7.1]
  def change
    create_table :outsider_erp_sale_attributions do |t|
      t.bigint :account_id, null: false
      t.string :company, null: false
      t.integer :order_number, null: false
      t.bigint :user_id
      t.jsonb :lines, null: false, default: []
      t.jsonb :approval, null: false, default: {}
      t.jsonb :history, null: false, default: []
      t.timestamps
    end
    add_index :outsider_erp_sale_attributions, [:account_id, :company, :order_number], unique: true,
                                                                                       name: 'index_outsider_erp_sale_attributions_on_order'
  end
end
