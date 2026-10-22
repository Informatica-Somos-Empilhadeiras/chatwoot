# OUTSIDER: cria um modelo de proposta novo, em branco (textos e condições padrão do tipo, papel timbrado do
# CRM) ou copiando outro modelo da conta. A cópia aponta para as mesmas imagens (cabeçalho, rodapé e
# elementos soltos em uso): nenhum arquivo é duplicado, e apagar um dos modelos não apaga a imagem do outro.
class Outsider::Crm::ProposalTemplateCopier
  def initialize(account)
    @account = account
  end

  def create(name:, kind:, source: nil)
    templates = Outsider::Crm::ProposalTemplate.where(account_id: @account.id)
    Outsider::Crm::ProposalTemplate.transaction do
      template = templates.new(name: name.to_s.strip, kind: kind, position: templates.maximum(:position).to_i + 1, active: true)
      template.content = source ? source.content.deep_dup : defaults(kind)
      template.save!
      copy_images(source, template) if source
      template
    end
  end

  private

  def defaults(kind)
    (kind.to_s == 'rental' ? Outsider::Crm::ProposalTemplateDefaults::RENTAL : Outsider::Crm::ProposalTemplateDefaults::SALE).deep_dup
  end

  def copy_images(source, template)
    %i[header_image footer_image].each do |slot|
      template.public_send(slot).attach(source.public_send(slot).blob) if source.public_send(slot).attached?
    end
    used = source.layout_images.attachments - source.unused_layout_images
    ids = used.to_h { |attachment| [attachment.id, attach_layout_image(template, attachment.blob)] }
    template.content = remap(template.content, ids)
    template.save!
  end

  def attach_layout_image(template, blob)
    template.layout_images.attach(blob)
    template.layout_images.attachments.max_by(&:id).id
  end

  # os elementos e os blocos de imagem passam a usar os anexos do modelo novo (mesmo arquivo)
  def remap(content, ids)
    content = content.merge('blocks' => content['blocks'].map { |block| remap_image(block, ids) }) if content['blocks'].is_a?(Array)
    return content unless content.key?('layout')

    layout = Outsider::Crm::ProposalTemplateLayout.layout(content)
    content.merge('layout' => layout.merge('elements' => layout['elements'].map { |element| remap_image(element, ids) }))
  end

  def remap_image(item, ids)
    item['image_id'] ? item.merge('image_id' => ids[item['image_id']]) : item
  end
end
