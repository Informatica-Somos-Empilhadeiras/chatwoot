# OUTSIDER: visualizar os documentos das conversas (WhatsApp, Telegram, site, e-mail) dentro do Chatwoot, só para ler.
#   PDF e texto (txt, csv...): abrem no próprio navegador, numa janela do Chatwoot.
#   Word, Excel e PowerPoint: pelo visualizador do Office na web (view.officeapps.live.com), que busca o arquivo num
#     endereço temporário assinado (vale 15 minutos). Esse visualizador só alcança o Chatwoot quando o endereço é público
#     (produção); no dev (localhost) esses arquivos ficam só com Baixar.
# Nenhuma cópia é criada: é sempre o mesmo anexo da conversa.
class Outsider::FileView
  WORD = %w[doc docx docm dotx dotm].freeze
  EXCEL = %w[xls xlsx xlsm xlsb].freeze
  POWERPOINT = %w[ppt pptx pptm pps ppsx potx].freeze
  TEXT = %w[txt csv tsv log json xml md].freeze
  # limites do visualizador do Office na web (Excel 5 MB, Word e PowerPoint 10 MB)
  OFFICE_LIMIT = { 'excel' => 5.megabytes, 'word' => 10.megabytes, 'powerpoint' => 10.megabytes }.freeze
  PDF_LIMIT = 60.megabytes
  TEXT_LIMIT = 2.megabytes
  EXPIRES = 15.minutes
  OFFICE_VIEWER = 'https://view.officeapps.live.com/op/embed.aspx?src='.freeze
  PATH = '/outsider/arquivo'.freeze

  def self.verifier
    ActiveSupport::MessageVerifier.new(Rails.application.key_generator.generate_key('outsider_file_view'),
                                       url_safe: true, digest: 'SHA256', serializer: JSON)
  end

  def self.site
    ENV.fetch('FRONTEND_URL', '').to_s.chomp('/')
  end

  # o visualizador do Office só busca arquivos num endereço https público
  def self.public_site?
    uri = URI.parse(site)
    uri.is_a?(URI::HTTPS) && uri.host.present? && !uri.host.match?(/\A(localhost|127\.|0\.0\.0\.0|10\.|192\.168\.)|\.local\z/)
  rescue URI::InvalidURIError
    false
  end

  # anexo de um endereço assinado (nil quando venceu ou foi mexido)
  def self.attachment_for(token)
    data = verifier.verified(token.to_s)
    data.is_a?(Hash) ? Attachment.find_by(id: data['a']) : nil
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
    nil
  end

  def initialize(attachment)
    @attachment = attachment
  end

  def payload
    kind, reason = kind_and_reason
    {
      id: @attachment.id, name: filename, extension: extension, size: size, kind: kind, reason: reason,
      view_url: view_url(kind), download_url: @attachment.file_url
    }
  end

  def extension
    @extension ||= (@attachment.extension.presence || File.extname(filename).delete_prefix('.')).to_s.downcase
  end

  def filename
    @attachment.file.attached? ? @attachment.file.filename.to_s : 'arquivo'
  end

  def size
    @attachment.file.attached? ? @attachment.file.byte_size : 0
  end

  # tipo que o navegador recebe ao abrir o endereço temporário
  def content_type
    return 'text/plain; charset=utf-8' if TEXT.include?(extension)
    return 'application/pdf' if extension == 'pdf'

    @attachment.file.content_type.presence || 'application/octet-stream'
  end

  # nome sem acentos nem espaços (o visualizador do Office olha a extensão no fim do endereço)
  def safe_filename
    base = File.basename(filename, '.*').parameterize.presence || 'arquivo'
    extension.present? ? "#{base.first(80)}.#{extension}" : base.first(80)
  end

  # endereço temporário do arquivo (relativo ao Chatwoot)
  def signed_path
    token = self.class.verifier.generate({ 'a' => @attachment.id }, expires_in: EXPIRES)
    "#{PATH}/#{token}/#{ERB::Util.url_encode(safe_filename)}"
  end

  private

  def kind_and_reason
    return %w[none missing] unless @attachment.file.attached?
    return limited('pdf', PDF_LIMIT) if extension == 'pdf'
    return limited('text', TEXT_LIMIT) if TEXT.include?(extension)

    family = office_family
    return %w[none unsupported] unless family
    return %w[none not_public] unless self.class.public_site?

    limited('office', OFFICE_LIMIT[family])
  end

  def limited(kind, limit)
    size > limit ? %w[none too_big] : [kind, nil]
  end

  def office_family
    return 'word' if WORD.include?(extension)
    return 'excel' if EXCEL.include?(extension)

    'powerpoint' if POWERPOINT.include?(extension)
  end

  def view_url(kind)
    return nil if kind == 'none'

    # PDF e texto abrem no mesmo endereço em que a pessoa está (a janela só aceita a mesma origem);
    # o Office na web precisa do endereço público completo
    kind == 'office' ? "#{OFFICE_VIEWER}#{CGI.escape("#{self.class.site}#{signed_path}")}" : signed_path
  end
end
