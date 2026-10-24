# OUTSIDER: o que a proposta aceita reservou no catálogo (Entrega 21), para devolver certo se ela deixar de ser
# aceita: [{ product_id, reserved, taken }], taken = quanto saiu da quantidade disponível.
class AddReservedStockToOutsiderCrmProposals < ActiveRecord::Migration[7.1]
  def change
    add_column :outsider_crm_proposals, :reserved_stock, :jsonb, default: [], null: false
  end
end
