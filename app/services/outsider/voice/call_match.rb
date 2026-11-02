# OUTSIDER: acha, no Chatwoot, a ligação que o telefone do navegador está vendo (Entregas 24 e 26). O navegador
# não conhece o id da ligação na central: manda o número de quem está do outro lado e a hora em que a ligação
# começou nele. Vale a ligação da pessoa com esse número que começou mais perto dessa hora. Usado pela gravação
# (Outsider::Voice::Recording) e por vincular a ligação a um negócio durante a conversa.
class Outsider::Voice::CallMatch
  # a central grava o começo quando a ligação chega nela; no navegador, quando toca (pode ser depois de várias
  # etapas de toque e da URA) ou quando ele disca
  BEFORE = 8.minutes
  AFTER = 1.minute

  def initialize(settings, user)
    @settings = settings
    @account = settings.account
    @user = user
  end

  # number: só dígitos (ramal ou telefone); started: hora em que começou no navegador
  def find(number, started)
    extension = @settings.agent_for(@user.id)&.dig('extension')
    return if started.nil? || number.blank? || extension.nil?

    Outsider::Voice::Call.where(account_id: @account.id, started_at: (started - BEFORE)..(started + AFTER))
                         .select { |call| mine?(call, extension) && same_party?(call, number) }
                         .min_by { |call| (call.started_at - started).abs }
  end

  def self.time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  private

  # ligação da pessoa; entre ramais, a central guarda quem atendeu, então vale também o ramal dela de um dos lados
  def mine?(call, extension)
    call.user_id == @user.id || (call.internal? && [call.from_number, call.to_number].include?(extension))
  end

  def same_party?(call, number)
    return call.internal? && [call.from_number, call.to_number].include?(number) if number.length <= 4

    Outsider::Voice::PhoneNumber.same?(call.customer_number, number)
  end
end
