# OUTSIDER: textos de envio do orçamento (assunto e corpo do e-mail, mensagem do WhatsApp), a partir dos modelos das
# Configurações com {numero}, {contato}, {cliente}, {total}, {pagamento} e {vendedor}. O agente ainda pode editar antes
# de enviar.
class Outsider::Erp::BudgetTexts
  def initialize(settings, report, user)
    @settings = settings
    @report = report
    @user = user
  end

  def subject = fill(@settings.data['quote_email_subject'])
  def body = fill(@settings.data['quote_email_body'])
  def whatsapp = fill(@settings.data['quote_whatsapp_text'])

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
      'pagamento' => @report['pagamento'].to_s, 'vendedor' => @report['vendedor'].presence || @user&.name.to_s
    }
  end

  # primeiro nome do A/C (ou do cliente), para o "Olá, ..."
  def contact_name
    name = @report.dig('cliente', 'contato').presence || @report.dig('cliente', 'nome').to_s
    name.split.first.to_s.capitalize
  end
end
