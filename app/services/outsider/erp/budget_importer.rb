# OUTSIDER: um orçamento feito no próprio Mais Prático entra no módulo de orçamento do chat só como registro
# (status "imported"), para mandar o PDF dele por WhatsApp ou e-mail e guardar os envios. Confere no ERP que o orçamento
# existe na unidade (só leitura). O mesmo orçamento vira um registro só por conta (índice único empresa + número): se ele
# foi feito no chat, volta o próprio rascunho gravado.
class Outsider::Erp::BudgetImporter
  class Invalid < StandardError; end

  MAX_NUMBER = 999_999_999

  def initialize(account, user)
    @account = account
    @user = user
    @settings = Outsider::Erp::Settings.new(account)
  end

  # name: o nome do cliente que a tela mostra (espelho dos orçamentos), só para a lista
  def import(company:, number:, contact:, name: nil, conversation_id: nil)
    company = company.to_s
    raise Invalid, 'company' unless @settings.companies.include?(company)

    number = Integer(number.to_s, exception: false)
    raise Invalid, 'number' unless number&.between?(1, MAX_NUMBER)

    find(company, number) || create(company, number, contact, name, conversation_id)
  end

  private

  def find(company, number)
    Outsider::Erp::Budget.find_by(account_id: @account.id, company: company, erp_number: number)
  end

  def create(company, number, contact, name, conversation_id)
    header = Outsider::Erp::QuoteReport.new(@account).header(company, number)
    Outsider::Erp::Budget.create!(
      account: @account, user: @user, contact: contact, status: :imported, company: company, erp_number: number,
      customer_code: header['cliente'].to_i.positive? ? header['cliente'].to_i : nil, customer_name: name.to_s.squish.first(120),
      conversation_id: Outsider::Erp::Budget.conversation_id_for(contact, conversation_id)
    )
  rescue ActiveRecord::RecordNotUnique
    find(company, number)
  end
end
