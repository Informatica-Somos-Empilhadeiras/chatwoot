# OUTSIDER: quem pode ouvir ou sussurrar na ligação de quem (Entrega 26).
#
# Supervisor: o administrador da conta (qualquer atendente) ou o gestor de uma unidade do CRM (os atendentes das
# unidades que ele gerencia). Ouve em silêncio (*80 + ramal: ninguém percebe) ou entra sussurrando (*81 + ramal:
# só os atendentes ouvem) e pode passar a falar com o cliente quando quiser.
# Convidado: o colega que o atendente chamou para sussurrar (convite de 2 minutos, usado uma vez). Para o cliente
# ouvir o convidado, o atendente precisa permitir (Outsider::Voice::Signals).
#
# A central pergunta aqui antes de cada monitoria; a resposta é texto simples para o plano de discagem: "ok" para
# ouvir, "supervisor:<id>" ou "guest:<id>" para sussurrar (vai num cabeçalho para o telefone do atendente) e vazio
# para recusar. Toda monitoria liberada fica registrada (Outsider::Voice::Monitor).
class Outsider::Voice::MonitorAccess
  INVITE_TTL = 2.minutes

  def initialize(settings)
    @settings = settings
    @account = settings.account
  end

  def self.invite_key(account_id, host_id, guest_id)
    "outsider_voice_invite:#{account_id}:#{host_id}:#{guest_id}"
  end

  # supervisor pode monitorar este atendente?
  def supervisor_of?(user_id, target_user_id)
    return false if user_id.nil? || target_user_id.nil? || user_id == target_user_id

    account_user = @account.account_users.find_by(user_id: user_id)
    access = account_user && Outsider::Crm::Access.new(account_user)
    return false unless access&.enabled? && access.manager?
    return true if access.administrator?

    Outsider::Crm::BusinessUnitMember.exists?(account_id: @account.id, business_unit_id: access.manager_unit_ids, user_id: target_user_id)
  end

  # a central pergunta: extension (quem pede), target (ramal monitorado), mode listen | whisper
  def authorize(linkedid:, extension:, target:, mode:)
    user_id = @settings.user_id_for_extension(extension)
    target_user_id = @settings.user_id_for_extension(target)
    return '' unless user_id && target_user_id && Outsider::Voice::Monitor::MODES.include?(mode)

    kind = monitor_kind(user_id, target_user_id, mode)
    return '' unless kind

    record(linkedid, user_id, target_user_id, mode, kind)
    mode == 'listen' ? 'ok' : "#{kind}:#{user_id}"
  end

  # fim da ligação de quem monitora (a central avisa o fim pelo mesmo linkedid)
  def finish(linkedid)
    Outsider::Voice::Monitor.where(account_id: @account.id, linkedid: linkedid, ended_at: nil).update_all(ended_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def monitor_kind(user_id, target_user_id, mode)
    return 'supervisor' if supervisor_of?(user_id, target_user_id)
    return unless mode == 'whisper'

    'guest' if Redis::Alfred.delete(self.class.invite_key(@account.id, target_user_id, user_id)).to_i.positive?
  end

  def record(linkedid, user_id, target_user_id, mode, kind)
    call = Outsider::Voice::Call.where(account_id: @account.id, user_id: target_user_id, ended_at: nil, status: :answered)
                                .where(started_at: Outsider::Voice::Wallboard::LIVE_WINDOW.ago..).order(started_at: :desc).first
    Outsider::Voice::Monitor.create_with(account: @account, user_id: user_id, target_user_id: target_user_id, call: call, mode: mode,
                                         kind: kind, started_at: Time.current).find_or_create_by!(linkedid: linkedid)
  end
end
