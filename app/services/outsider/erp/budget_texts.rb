# OUTSIDER: textos de envio do orçamento (prefix 'quote'), do relatório da OS ('os') e da nota fiscal ('nf'): assunto e
# corpo do e-mail e mensagem do WhatsApp, a partir dos modelos das Configurações com {numero}, {contato}, {cliente},
# {total}, {pagamento}, {vendedor} e {tecnico}. Também volta o corpo e a mensagem com o {contato} ainda por trocar
# (templates), para a tela pôr o nome do contato que a pessoa escolher. Sem contato, a saudação fica genérica ("Olá!").
# O agente ainda pode editar antes de enviar.
class Outsider::Erp::BudgetTexts
  # contact_name: o contato escolhido no chat, para o "Olá, ..."; sem ele, vale o A/C do orçamento (contact_fallback)
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
    {
      subject: subject, body: body, whatsapp: whatsapp, contact_fallback: first_name(@report.dig('cliente', 'contato')),
      templates: { body: fill(@settings.data["#{@prefix}_email_body"], contact: false),
                   whatsapp: fill(@settings.data["#{@prefix}_whatsapp_text"], contact: false) }
    }
  end

  private

  # contact: false deixa o {contato} para a tela; sem nome de contato, "Olá, {contato}!" vira "Olá!"
  def fill(template, contact: true)
    template = template.to_s
    template = template.gsub(/,?[ \t]*\{contato\}/, '') if contact && values['contato'].blank?
    known = contact ? values : values.except('contato')
    template.gsub(/\{(\w+)\}/) { known.fetch(Regexp.last_match(1), Regexp.last_match(0)) }
  end

  def values
    @values ||= {
      'numero' => @report['numero'].to_s, 'contato' => contact_name, 'cliente' => @report.dig('cliente', 'nome').to_s,
      'total' => ActiveSupport::NumberHelper.number_to_currency(@report['total'].to_f, unit: 'R$ ', separator: ',', delimiter: '.'),
      'pagamento' => @report['pagamento'].to_s, 'vendedor' => @report['vendedor'].presence || @user&.name.to_s,
      'tecnico' => @report.dig('servico', 'tecnico').to_s
    }
  end

  # primeiro nome do contato escolhido ou do A/C do orçamento, para o "Olá, ..." (nunca o nome da empresa)
  def contact_name = first_name(@contact_name.presence || @report.dig('cliente', 'contato'))

  def first_name(name) = name.to_s.split.first.to_s.capitalize
end
