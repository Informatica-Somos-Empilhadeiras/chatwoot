# OUTSIDER: o PDF do orçamento que vai para o cliente. Cada versão enviada vira um único arquivo (blob do Active Storage),
# reconhecido pelo SHA-256 do conteúdo: mandar o mesmo orçamento de novo (outro contato, outro canal) reaproveita o
# arquivo; se o orçamento mudou no ERP, o conteúdo muda e sai um arquivo novo (o Prawn monta os mesmos bytes para os
# mesmos dados). Como nas propostas do CRM (Outsider::Crm::ProposalDocument). Sai no modelo de orçamento escolhido, se houver.
class Outsider::Erp::BudgetDocument
  attr_reader :digest

  def initialize(budget, report)
    @budget = budget
    @pdf = Outsider::Erp::Prints::Document.quote(budget.account, report)
  end

  def filename = @pdf.filename

  def blob
    @blob ||= existing_blob || upload
  end

  private

  def content
    @content ||= @pdf.render.tap { |bytes| @digest = Digest::SHA256.hexdigest(bytes) }
  end

  def existing_blob
    content
    previous = @budget.sends.where(digest: digest).order(:id).includes(document_attachment: :blob).find { |send| send.document.attached? }
    previous&.document&.blob
  end

  def upload
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(content), filename: filename, content_type: 'application/pdf')
  end
end
