# OUTSIDER: nota privada na conversa dizendo o que mudou numa OS do ERP (fica no histórico do atendimento, não vai
# para o cliente). Só formata e posta; quem decide se posta é o Outsider::Erp::Writer (note_on_change).
class Outsider::Erp::ChangeNote
  MAX = 300

  def initialize(user:, conversation:)
    @user = user
    @conversation = conversation
  end

  def post(order:, field:, from:, to:)
    content = I18n.t('outsider_erp.note', os: order['CodigoOS'], company: order['Empresa'], field: label(field),
                                          from: display(field, from), to: display(field, to), locale: :pt_BR)
    Messages::MessageBuilder.new(@user, @conversation, { content: content, private: true }).perform
  end

  private

  def label(field) = I18n.t("outsider_erp.fields.#{field}", default: field, locale: :pt_BR)

  # datas em dd/mm/aaaa (o ERP manda "2026-11-11T03:00:00.000Z"; a tela manda "2026-11-20")
  def display(field, value)
    return '—' if value.blank?
    return value.to_s.truncate(MAX) unless Outsider::Erp::Settings::FIELD_KINDS[field] == 'date'

    Date.parse(value.to_s).strftime('%d/%m/%Y')
  rescue Date::Error
    value.to_s.truncate(MAX)
  end
end
