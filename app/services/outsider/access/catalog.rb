# OUTSIDER: as telas que os perfis de acesso controlam. Cada uma tem os níveis que fazem sentido nela, o padrão dos
# perfis prontos (Agente e Técnico) e o que a API recusa (ApiGuard: controladores por tela). As telas e as rotas do
# painel ficam em app/javascript/dashboard/routes/dashboard/outsider/access/catalog.js (mesmas chaves).
module Outsider::Access::Catalog
  LEVELS = %w[none view use manage].freeze
  RANK = LEVELS.each_with_index.to_h.freeze

  # group: telefonia, atendimento, vendas, erp, relatorios; admin_only: só administrador (o perfil não libera); parent: tela mãe (a
  # filha sem escolha no perfil segue a mãe e nunca passa dela)
  SCREENS = [
    { key: 'phone', group: 'telefonia', levels: %w[none use], agent: 'use', technician: 'use' },
    { key: 'phone_outbound', group: 'telefonia', levels: %w[none use], agent: 'use', technician: 'use' },
    { key: 'voice_panel', group: 'telefonia', levels: %w[none view use], agent: 'use', technician: 'none' },
    { key: 'voice_recordings', group: 'telefonia', levels: %w[none view use], agent: 'use', technician: 'none' },
    { key: 'voice_monitor', group: 'telefonia', levels: %w[none use manage], agent: 'use', technician: 'none' },
    { key: 'voice_admin', group: 'telefonia', levels: %w[none manage], agent: 'none', technician: 'none', admin_only: true },
    { key: 'conversations', group: 'atendimento', levels: %w[none view use], agent: 'use', technician: 'none' },
    { key: 'contacts', group: 'atendimento', levels: %w[none view use], agent: 'use', technician: 'view' },
    { key: 'whatsapp_status', group: 'atendimento', levels: %w[none view use], agent: 'use', technician: 'none' },
    { key: 'teams', group: 'atendimento', levels: %w[none use], agent: 'use', technician: 'use' },
    # OUTSIDER (Aplicativos): Gmail, Agenda e Drive com a conta Google de cada pessoa
    { key: 'google', group: 'atendimento', levels: %w[none use], agent: 'use', technician: 'use' },
    { key: 'crm', group: 'vendas', levels: %w[none view use], agent: 'use', technician: 'none' },
    # OUTSIDER (ERP): a seção ERP Mais Prático (menu e API) e uma linha por aba. Orçamentos: Usa cria, edita e envia;
    # OS: Usa muda substatus e campos e envia o relatório; Pedidos: Usa informa o técnico e a OS (só no chat);
    # Produtos: só consulta (com as fotos); Clientes: Usa cadastra cliente no ERP
    { key: 'erp', group: 'erp', levels: %w[none view use], agent: 'use', technician: 'none' },
    { key: 'erp_quotes', group: 'erp', levels: %w[none view use], agent: 'use', technician: 'none', parent: 'erp' },
    { key: 'erp_orders', group: 'erp', levels: %w[none view use], agent: 'use', technician: 'none', parent: 'erp' },
    { key: 'erp_sales', group: 'erp', levels: %w[none view use], agent: 'use', technician: 'none', parent: 'erp' },
    { key: 'erp_invoices', group: 'erp', levels: %w[none view use], agent: 'use', technician: 'none', parent: 'erp' },
    { key: 'erp_products', group: 'erp', levels: %w[none view], agent: 'view', technician: 'none', parent: 'erp' },
    # Locação e máquinas: contratos, máquinas e faturas de locação (só leitura)
    { key: 'erp_rentals', group: 'erp', levels: %w[none view], agent: 'view', technician: 'none', parent: 'erp' },
    { key: 'erp_clients', group: 'erp', levels: %w[none use], agent: 'use', technician: 'none', parent: 'erp' },
    # OUTSIDER (Relatórios do ERP, abas da seção ERP): a linha geral e uma por relatório (os próximos entram aqui). Começa fechada para
    # agente e técnico: o administrador libera no perfil de quem precisa (comissão é informação sensível).
    { key: 'reports', group: 'relatorios', levels: %w[none view], agent: 'none', technician: 'none', parent: 'erp' },
    { key: 'reports_technicians', group: 'relatorios', levels: %w[none view], agent: 'none', technician: 'none', parent: 'reports' }
  ].freeze
  BY_KEY = SCREENS.index_by { |screen| screen[:key] }.freeze
  KEYS = BY_KEY.keys.freeze

  # API do Chatwoot e dos módulos por tela (controller_path). Os da telefonia que não estão aqui (o telefone em si)
  # conferem o acesso no próprio controlador (Api::V1::Accounts::Outsider::VoiceController).
  # (nil = fica de fora: o acesso ao CRM responde "sem acesso" pelo perfil, ver Crm::AccessesController)
  CONTROLLERS = [
    [%r{\Aapi/v1/accounts/outsider/crm/accesses\z}, nil],
    [%r{\Aapi/v1/accounts/outsider/crm/(calls|call_goals)\z}, 'voice_panel'],
    [%r{\Aapi/v1/accounts/outsider/crm/call_recordings\z}, 'voice_recordings'],
    [%r{\Aapi/v1/accounts/outsider/crm/(voice_settings|ivr_flows)\z}, 'voice_admin'],
    [%r{\Aapi/v1/accounts/outsider/crm/}, 'crm'],
    [%r{\Aapi/v1/accounts/(conversations|search)(/|\z)}, 'conversations'],
    [%r{\Aapi/v1/accounts/outsider/(conversation_searches|message_searches|conversation_histories|message_forwards|whatsapp_messages|
         contact_cards|locations|transfer_requests|stickers|sticker_packs)\z}x, 'conversations'],
    [%r{\Aapi/v1/accounts/(contacts|companies)(/|\z)}, 'contacts'],
    [%r{\Aapi/v1/accounts/outsider/whatsapp_statuses\z}, 'whatsapp_status'],
    [%r{\Aapi/v1/accounts/outsider/teams_}, 'teams'],
    [%r{\Aapi/v1/accounts/outsider/apps/microsoft_}, 'teams'], # Outlook e OneDrive seguem o Teams
    [%r{\Aapi/v1/accounts/outsider/apps/google_}, 'google'],
    [%r{\Aapi/v1/accounts/outsider/erp/}, 'erp'],
    [%r{\Aapi/v1/accounts/outsider/reports/}, 'reports']
  ].freeze

  # ações que não mudam nada para quem só vê (marcar como lida, avisar que está digitando)
  VIEW_SAFE_ACTIONS = %w[update_last_seen toggle_typing_status search filter].freeze

  module_function

  def levels(screen)
    BY_KEY.dig(screen.to_s, :levels) || []
  end

  def parent(screen)
    BY_KEY.dig(screen.to_s, :parent)
  end

  def admin_only?(screen)
    BY_KEY.dig(screen.to_s, :admin_only) == true
  end

  # nível pedido que a tela não tem cai no mais alto que ela tem abaixo dele
  def clamp(screen, level)
    allowed = levels(screen)
    return 'none' if allowed.empty?
    return level if allowed.include?(level)

    allowed.select { |item| RANK[item] <= RANK.fetch(level.to_s, 0) }.max_by { |item| RANK[item] } || 'none'
  end

  def default_level(kind, screen)
    entry = BY_KEY[screen.to_s]
    return 'none' unless entry

    case kind.to_s
    when 'administrator' then entry[:levels].max_by { |item| RANK[item] }
    when 'technician' then entry[:technician]
    else entry[:agent]
    end
  end

  def defaults(kind)
    KEYS.index_with { |key| default_level(kind, key) }
  end

  def screen_for_controller(path)
    CONTROLLERS.find { |pattern, _screen| pattern.match?(path) }&.last
  end

  def rank(level) = RANK.fetch(level.to_s, 0)

  def as_json
    SCREENS.map { |screen| screen.slice(:key, :group, :levels, :admin_only, :parent).merge(defaults: screen.slice(:agent, :technician)) }
  end
end
