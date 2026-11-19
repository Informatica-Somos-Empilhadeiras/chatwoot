# OUTSIDER: liga o catálogo e as propostas do CRM ao ERP Mais Prático.
# - produtos: CodigoProduto real da unidade, para os itens do orçamento saírem com imposto certo;
# - propostas: a unidade (banco) e o número do orçamento gerado no ERP, mais quando foi sincronizado (idempotência).
# Só adiciona colunas (rollback remove). Ver Outsider::Erp::QuoteCreator / Outsider::Erp::Catalog.
class AddErpLinksToOutsiderCrm < ActiveRecord::Migration[7.1]
  def change
    add_column :outsider_crm_products, :erp_codigo_produto, :integer

    add_column :outsider_crm_proposals, :erp_company, :string
    add_column :outsider_crm_proposals, :erp_quote_number, :integer
    add_column :outsider_crm_proposals, :erp_synced_at, :datetime
  end
end
