# OUTSIDER: o PDF de uma OS ou de um orçamento do ERP no modelo escolhido para o caso (Outsider::Erp::Prints::Bindings)
# ou, sem escolha, no relatório original (Outsider::Erp::ServiceOrderPdf / QuotePdf, igual ao do Mais Prático). Quem chama
# recebe sempre algo com filename e render, então as telas e o envio ao cliente não mudam.
# - OS: sem nenhum modelo escolhido, é exatamente o caminho de antes. Com modelo, lê a OS sem as fotos, escolhe pelo tipo
#   de atendimento e só então busca as fotos que o modelo mostra (seções filtradas ficam sem buscar);
# - orçamento: o padrão do orçamento (o do ERP, o feito no chat e a prévia do rascunho).
class Outsider::Erp::Prints::Document
  attr_reader :filename

  def initialize(template, values, filename:)
    @template = template
    @values = values
    @filename = filename
  end

  def render
    Outsider::Erp::Prints::Pdf.new(@template.content, @values, images: self.class.images_of(@template),
                                                               title: @filename.delete_suffix('.pdf')).render
  end

  class << self
    def service_order(account, company, code)
      reporter = Outsider::Erp::ServiceOrderReport.new(account)
      bindings = Outsider::Erp::Prints::Bindings.new(account)
      return Outsider::Erp::ServiceOrderPdf.new(reporter.build(company, code)) unless bindings.uses_templates?('os')

      report = reporter.build(company, code, photos: false)
      template = bindings.template('os', report.dig('servico', 'tipo_atendimento'))
      return Outsider::Erp::ServiceOrderPdf.new(reporter.with_photos(report)) unless template

      for_service_order(account, template, report, reporter)
    end

    # com um modelo já escolhido (a pré-visualização do estúdio com uma OS de verdade)
    def for_service_order(account, template, report, reporter)
      wanted = photo_filter(template.content)
      report = reporter.with_photos(report, &wanted) if wanted
      report = report.merge('emitente' => full_emitter(account, report['empresa'], report['emitente']))
      new(template, values(account, 'os', report), filename: Outsider::Erp::ServiceOrderPdf.new(report).filename)
    end

    def quote(account, report, template: nil)
      original = Outsider::Erp::QuotePdf.new(report)
      template ||= Outsider::Erp::Prints::Bindings.new(account).template('quote')
      return original unless template

      new(template, values(account, 'quote', report), filename: original.filename)
    end

    def values(account, kind, report)
      company = (report['empresa'] || report['company']).to_s
      unit = Outsider::Erp::Settings.new(account).company_names[company]
      Outsider::Erp::Prints::Values.new(kind, report, unit_name: unit.presence || company).build
    end

    # imagens enviadas no modelo (logo próprio, imagens soltas): id do anexo => bytes
    def images_of(template)
      used = Outsider::Erp::Prints::Content.image_ids(template.content)
      template.images.attachments.select { |attachment| used.include?(attachment.id) }.to_h do |attachment|
        [attachment.id, attachment.download]
      rescue StandardError
        [attachment.id, nil]
      end
    end

    # que seções do checklist o modelo mostra com fotos: nil = nenhuma (não busca foto nenhuma); bloco sem filtro = todas
    def photo_filter(content)
      names = photo_blocks(content).map { |block| Array(block['sections']).map { |name| plain(name) } }
      return if names.empty?

      return ->(_name) { true } if names.any?(&:empty?)

      allowed = names.flatten
      ->(name) { allowed.include?(plain(name)) }
    end

    def photo_blocks(content)
      Array(content['blocks']).select { |block| block['type'] == 'checklist' && block['photos'] != 'without' }
    end

    def plain(text) = I18n.transliterate(text.to_s).squish.downcase

    # o relatório da OS só traz nome, telefone e e-mail da própria OS; o endereço e o site vêm da empresa da unidade
    def full_emitter(account, company, own)
      base = Outsider::Erp::Emitter.new(account).data_for(company.to_s)
      base.merge(own.to_h.compact_blank)
    rescue StandardError
      own.to_h
    end
  end
end
