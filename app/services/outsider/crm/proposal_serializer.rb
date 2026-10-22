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
                     can_delete: access&.delete?(proposal),
                     can_send: access&.send?(proposal)
                   )
  end

  def proposal(proposal, access: nil)
    proposal_row(proposal, access: access).merge(
      proposal.slice(:customer, :conditions, :signer, :notes, :contact_id, :opportunity_id, :owner_id),
      items: proposal.items.map { |item| item(item) },
      created_by: Outsider::Crm::Serializer.user(proposal.created_by),
      sends: sends(proposal)
    )
  end

  # Envios, do mais novo ao mais antigo. A versão conta os PDFs diferentes na ordem em que saíram; o
  # arquivo é o mesmo que foi para o cliente. message_status é o da mensagem na conversa (enviada,
  # entregue, lida ou falhou), quando o canal informa.
  def sends(proposal)
    records = proposal.sends.order(:id).includes(:user, document_attachment: :blob).to_a
    versions = records.filter_map(&:digest).uniq.each_with_index.to_h { |digest, index| [digest, index + 1] }
    lookup = send_lookups(records)
    records.reverse.map { |record| send_row(record, versions[record.digest], lookup) }
  end

  def send_row(record, version, lookup)
    record.slice(:id, :channel, :recipient, :status, :error, :created_at, :contact_id).merge(
      contact_name: lookup[:contacts][record.contact_id], user: Outsider::Crm::Serializer.user(record.user),
      version: version, file_url: file_path(record.document),
      conversation_display_id: lookup[:conversations][record.conversation_id], message_status: lookup[:messages][record.message_id]
    )
  end

  def send_lookups(records)
    {
      conversations: Conversation.where(id: records.filter_map(&:conversation_id)).pluck(:id, :display_id).to_h,
      messages: Message.where(id: records.filter_map(&:message_id)).pluck(:id, :status).to_h,
      contacts: Contact.where(id: records.filter_map(&:contact_id)).pluck(:id, :name).to_h
    }
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
