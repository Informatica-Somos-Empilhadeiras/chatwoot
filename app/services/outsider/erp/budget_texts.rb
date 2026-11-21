# OUTSIDER: textos de envio do orçamento (prefix 'quote') e do relatório da OS (prefix 'os'): assunto e corpo do e-mail e
# mensagem do WhatsApp, a partir dos modelos das Configurações com {numero}, {contato}, {cliente}, {total}, {pagamento},
# {vendedor} e {tecnico}. O agente ainda pode editar antes de enviar.
class Outsider::Erp::BudgetTexts
  # contact_name: o contato escolhido no chat, para o "Olá, ..." (a OS não tem A/C); sem ele, vale o do relatório
  def initialize(settings, report, user, prefix: 'quote', contact_name: nil)
    @settings = settings
    @report = report
    @user = user
    @prefix = prefix
    @contact_name = contact_name
  end

  def subject = fill(@settings.data["#{@prefix}_email_subject"])
  def body = fill(@settings.data["#{@prefix}_email_body"])
  def whatsapp = fill(@settings.data["#{@prefix}_whatsapp_text"])

  def as_json(*)
    { subject: subject, body: body, whatsapp: whatsapp }
  end

  private

  def fill(template)
    template.to_s.gsub(/\{(\w+)\}/) { values.fetch(Regexp.last_match(1), Regexp.last_match(0)) }
  end

  def values
    @values ||= {
      'numero' => @report['numero'].to_s, 'contato' => contact_name, 'cliente' => @report.dig('cliente', 'nome').to_s,
      'total' => ActiveSupport::NumberHelper.number_to_currency(@report['total'].to_f, unit: 'R$ ', separator: ',', delimiter: '.'),
      'pagamento' => @report['pagamento'].to_s, 'vendedor' => @report['vendedor'].presence || @user&.name.to_s,
      'tecnico' => @report.dig('servico', 'tecnico').to_s
    }
  end

  # primeiro nome do contato escolhido, do A/C ou do cliente, para o "Olá, ..."
  def contact_name
    name = @contact_name.presence || @report.dig('cliente', 'contato').presence || @report.dig('cliente', 'nome').to_s
    name.split.first.to_s.capitalize
  end
end
