# OUTSIDER: o fuso da Telefonia e a gravação de ligações (Entrega 24), em Telefonia > Configurações, junto
# com o resto de Outsider::Voice::Settings. O fuso vale para o painel, as ligações e os relatórios, para todo
# mundo (antes as horas seguiam o navegador de quem via).
module Outsider::Voice::SettingsExtras
  DEFAULT_ZONE = 'America/Sao_Paulo'.freeze
  ZONES = %w[America/Sao_Paulo America/Bahia America/Fortaleza America/Recife America/Belem America/Manaus America/Cuiaba
             America/Campo_Grande America/Porto_Velho America/Boa_Vista America/Rio_Branco America/Noronha].freeze
  # tela antiga que não manda os campos novos: fica o que está guardado
  EXTRAS = %w[time_zone recording].freeze

  def time_zone
    ActiveSupport::TimeZone[data['time_zone'].to_s] || ActiveSupport::TimeZone[DEFAULT_ZONE]
  end

  # botão Gravar no telefone: o administrador pode desligar
  def recording?
    data['recording'] != false
  end

  private

  def clean_extras(params)
    params = data.slice(*EXTRAS).merge(params.slice(*EXTRAS))
    { 'time_zone' => choice(params['time_zone'], ZONES, 'time_zone'), 'recording' => boolean(params['recording']) }
  end
end
