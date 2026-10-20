# OUTSIDER: base das configurações que mudam com o tempo (metas e comissão). Ficam em
# accounts.internal_attributes por mês de início ("2026-10" => {...}): o que foi gravado para um
# mês vale para ele e para os seguintes até a próxima alteração, e os meses anteriores guardam o
# valor da época. Sem tabela nova.
class Outsider::Crm::MonthlyConfig
  MONTH = /\A\d{4}-(0[1-9]|1[0-2])\z/

  class Invalid < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super(errors.join(', '))
    end
  end

  def self.current_month
    Time.zone.today.strftime('%Y-%m')
  end

  def self.month(value)
    value.to_s.match?(MONTH) ? value.to_s : current_month
  end

  def self.range(month)
    Date.strptime(month, '%Y-%m').in_time_zone.all_month
  end

  def initialize(account)
    @account = account
  end

  # [mês de início, dados] valendo no mês pedido; sem nada gravado até ali, [nil, {}]
  def version(month)
    from = versions.keys.select { |key| key <= month }.max
    [from, from ? versions[from] : {}]
  end

  private

  def versions
    @account.internal_attributes[self.class::KEY].to_h
  end

  def store(month, data)
    @account.with_lock do
      merged = versions.merge(month => data)
      # update_columns para não esbarrar nas validações de outros campos da conta
      @account.update_columns(internal_attributes: @account.internal_attributes.merge(self.class::KEY => merged)) # rubocop:disable Rails/SkipsModelValidations
    end
    Outsider::Crm::LiveUpdates.broadcast(@account.id, 'config')
  end

  def unit_ids
    @unit_ids ||= Outsider::Crm::BusinessUnit.where(account_id: @account.id).pluck(:id)
  end

  def user_ids
    @user_ids ||= @account.account_users.pluck(:user_id)
  end
end
