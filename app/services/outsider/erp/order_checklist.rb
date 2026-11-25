# OUTSIDER: se o checklist de uma OS já foi respondido no app do técnico e chegou ao ERP (sincronizado). Os botões
# Emitir relatório e Enviar da OS só ficam ativos com a OS concluída e o checklist respondido. Uma leitura só
# (DadosCheckList_PDF, a mesma do relatório), guardada um pouco no cache: respondido 1 hora, ainda não 2 minutos.
class Outsider::Erp::OrderChecklist
  ANSWERED_TTL = 1.hour
  PENDING_TTL = 2.minutes

  def initialize(account, client: nil)
    @account = account
    @client = client
  end

  def answered?(company, number)
    key = "outsider:erp:checklist:#{@account.id}:#{company}:#{number.to_i}"
    cached = Rails.cache.read(key)
    return cached unless cached.nil?

    answered = rows(company, number).any? { |row| answered_row?(row) }
    Rails.cache.write(key, answered, expires_in: answered ? ANSWERED_TTL : PENDING_TTL)
    answered
  end

  private

  def rows(company, number)
    client.service_order_report('DadosCheckList_PDF', company, number)
  end

  def client
    @client ||= Outsider::Erp::Client.new(Outsider::Erp::Settings.new(@account))
  end

  # resposta na chegada/saída ou uma foto desta OS
  def answered_row?(row)
    %w[VALOR_INI VALOR VALOR_FIM].any? { |field| row[field].to_s.strip.present? } ||
      row['CaminhoIMG'].to_s.strip.match?(Outsider::Erp::ServiceOrderReport::PHOTO_REF)
  end
end
