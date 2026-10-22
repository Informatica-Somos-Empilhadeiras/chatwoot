# OUTSIDER: o PDF que vai para o cliente. Cada versão enviada vira um único arquivo (blob do Active Storage),
# reconhecido pelo SHA-256 do conteúdo: mandar a mesma versão de novo (para outro contato, por outro canal)
# reaproveita o arquivo; alterar a proposta muda o conteúdo e gera um arquivo novo. O Prawn monta sempre os
# mesmos bytes para os mesmos dados, então a comparação funciona.
class Outsider::Crm::ProposalDocument
  attr_reader :digest

  def initialize(proposal)
    @proposal = proposal
  end

  def blob
    @blob ||= existing_blob || upload
  end

  private

  def pdf
    @pdf ||= Outsider::Crm::ProposalPdf.new(@proposal)
  end

  def content
    @content ||= pdf.render.tap { |bytes| @digest = Digest::SHA256.hexdigest(bytes) }
  end

  def existing_blob
    content
    previous = @proposal.sends.where(digest: digest).order(:id).includes(document_attachment: :blob).find { |send| send.document.attached? }
    previous&.document&.blob
  end

  def upload
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(content), filename: pdf.filename, content_type: 'application/pdf')
  end
end
