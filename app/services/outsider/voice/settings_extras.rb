# OUTSIDER: o fuso da Telefonia e a gravação de ligações (Entrega 24), em Telefonia > Configurações, junto
# com o resto de Outsider::Voice::Settings. O fuso vale para o painel, as ligações e os relatórios, para todo
# mundo (antes as horas seguiam o navegador de quem via).
#
# Entrega 25: gravar sozinho toda ligação com cliente (desligado até o administrador ligar) e por quantos dias
# a gravação fica guardada (1 ano, se ninguém mudar; Outsider::Voice::RecordingCleanupJob apaga as antigas).
# Os custos e as filiais ficam em Outsider::Voice::SettingsBilling.
module Outsider::Voice::SettingsExtras
  include Outsider::Voice::SettingsBilling

  DEFAULT_ZONE = 'America/Sao_Paulo'.freeze
  ZONES = %w[America/Sao_Paulo America/Bahia America/Fortaleza America/Recife America/Belem America/Manaus America/Cuiaba
             America/Campo_Grande America/Porto_Velho America/Boa_Vista America/Rio_Branco America/Noronha].freeze
  RECORDING_DAYS = (30..1825)
  DEFAULT_RECORDING_DAYS = 365
  # tela antiga que não manda os campos novos: fica o que está guardado
  EXTRAS = %w[time_zone recording auto_record recording_days].freeze

  def time_zone
    ActiveSupport::TimeZone[data['time_zone'].to_s] || ActiveSupport::TimeZone[DEFAULT_ZONE]
  end

  # botão Gravar no telefone: o administrador pode desligar
  def recording?
    data['recording'] != false
  end

  # o telefone começa a gravar sozinho quando a ligação com cliente é atendida
  def auto_record?
    data['auto_record'] == true
  end

  def recording_days
    days = data['recording_days'].to_i
    RECORDING_DAYS.cover?(days) ? days : DEFAULT_RECORDING_DAYS
  end

  private

  def clean_extras(params)
    values = data.slice(*EXTRAS).merge(params.slice(*EXTRAS))
    {
      'time_zone' => choice(values['time_zone'], ZONES, 'time_zone'), 'recording' => boolean(values['recording']),
      'auto_record' => boolean(values['auto_record']), 'recording_days' => clean_recording_days(values['recording_days'])
    }.merge(clean_billing(params))
  end

  def clean_recording_days(value)
    days = Integer(value.presence || DEFAULT_RECORDING_DAYS, exception: false)
    @errors << 'recording_days' unless days && RECORDING_DAYS.cover?(days)
    days
  end
end
