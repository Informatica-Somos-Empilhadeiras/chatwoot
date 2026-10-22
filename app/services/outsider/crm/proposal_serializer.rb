# OUTSIDER: formato JSON do catálogo, dos modelos e das propostas (controllers de Outsider::Crm).
# As imagens vão como caminho do arquivo no armazenamento do Chatwoot: a tela mostra o mesmo arquivo.
module Outsider::Crm::ProposalSerializer
  module_function

  def product(product)
    product.slice(:id, :kind, :name, :code, :brand, :description, :specs, :features, :sale_price_cents, :rental_price_cents,
                  :active, :created_at, :updated_at).merge(image_url: file_path(product.image))
  end

  def template(template)
    template.slice(:id, :name, :kind, :active, :position, :content).merge(
      header_image_url: file_path(template.header_image),
      footer_image_url: file_path(template.footer_image)
    )
  end

  # Linha da lista de propostas
  def proposal_row(proposal, access: nil)
    proposal.slice(:id, :number, :kind, :status, :title, :total_cents, :currency, :issued_on, :valid_until, :business_unit_id,
                   :template_id, :sent_at, :decided_at, :created_at, :updated_at).merge(
                     code: proposal.code,
                     display_status: proposal.display_status,
                     customer_company: proposal.customer['company'],
                     contact: Outsider::Crm::Serializer.contact(proposal.contact),
                     owner: Outsider::Crm::Serializer.user(proposal.owner),
                     opportunity: opportunity_link(proposal.opportunity),
                     can_edit: access&.edit?(proposal),
                     can_edit_content: access&.edit_content?(proposal),
                     can_delete: access&.delete?(proposal)
                   )
  end

  def proposal(proposal, access: nil)
    proposal_row(proposal, access: access).merge(
      proposal.slice(:customer, :conditions, :signer, :notes, :contact_id, :opportunity_id, :owner_id),
      items: proposal.items.map { |item| item(item) },
      created_by: Outsider::Crm::Serializer.user(proposal.created_by)
    )
  end

  def item(item)
    item.slice(:id, :product_id, :position, :description, :unit_price_cents, :discount_cents, :total_cents, :show_details, :details)
        .merge(quantity: item.quantity.to_f, image_url: file_path(item.image))
  end

  def opportunity_link(opportunity)
    opportunity && { id: opportunity.id, code: opportunity.code, title: opportunity.title, status: opportunity.status,
                     business_unit_id: opportunity.business_unit_id }
  end

  def file_path(attachment)
    return unless attachment&.attached?

    Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true)
  end
end
