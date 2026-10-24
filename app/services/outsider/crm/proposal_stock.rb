# OUTSIDER: estoque do catálogo na proposta aceita (Entrega 21). Ao aceitar, cada item do catálogo que controla
# quantidade passa a quantidade da proposta (arredondada para cima) para "reservada" e tira o mesmo tanto da
# "disponível" (até zerar). O que foi mexido fica anotado na proposta (reserved_stock) para, se ela deixar de
# ser aceita, devolver exatamente isso. Roda na transação da mudança de situação, antes de gravá-la, com os
# produtos travados.
class Outsider::Crm::ProposalStock
  def initialize(proposal)
    @proposal = proposal
  end

  def apply(status)
    accepting = status.to_s == 'accepted'
    return if @proposal.accepted? == accepting

    @proposal.reserved_stock = accepting ? reserve : release
  end

  private

  def reserve
    quantities = @proposal.items.reorder(nil).where.not(product_id: nil).group(:product_id).sum(:quantity)
    locked_products(quantities.keys).filter_map do |product|
      reserve_product(product, quantities[product.id].ceil) unless product.available_quantity.nil? && product.reserved_quantity.nil?
    end
  end

  def reserve_product(product, quantity)
    taken = [product.available_quantity.to_i, quantity].min
    product.update!(reserved_quantity: product.reserved_quantity.to_i + quantity,
                    available_quantity: product.available_quantity && (product.available_quantity - taken))
    { 'product_id' => product.id, 'reserved' => quantity, 'taken' => taken }
  end

  def release
    rows = @proposal.reserved_stock.index_by { |row| row['product_id'] }
    locked_products(rows.keys).each do |product|
      row = rows[product.id]
      product.update!(reserved_quantity: product.reserved_quantity && [product.reserved_quantity - row['reserved'], 0].max,
                      available_quantity: product.available_quantity && (product.available_quantity + row['taken']))
    end
    []
  end

  # Em ordem de id, para duas propostas aceitas ao mesmo tempo não se travarem
  def locked_products(ids)
    Outsider::Crm::Product.where(account_id: @proposal.account_id, id: ids).order(:id).lock
  end
end
