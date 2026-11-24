# OUTSIDER: configuração da integração com o ERP Mais Prático (Inntegra), em accounts.internal_attributes. Só o
# administrador muda (Ordens de serviço > Configurações).
#
# Regras de segurança desta integração (não afrouxar):
# - leitura só pela API web do ERP (a mesma que o painel web deles usa); nunca pelo banco MySQL;
# - escrita só nos endpoints confirmados por captura de uma ação real no ERP (UpdateSubStatusOS + GravaHistoricoSubStatusOS,
#   UpdateDefeitos) e nos que o administrador cadastrar depois de capturar no próprio navegador; começa desligada;
# - o endereço da API precisa ser https num subdomínio inntegra.com.br, e as empresas (bancos) são só as da lista daqui:
#   a tela nunca escolhe a empresa de uma gravação (vem da própria OS, conferida contra esta lista).
class Outsider::Erp::Settings
  include Outsider::Erp::Settings::Nextcloud
  include Outsider::Erp::Settings::CompanyNames
  include Outsider::Erp::Settings::Reports

  KEY = 'outsider_erp'.freeze
  HOST = /\A[a-z0-9-]+(\.[a-z0-9-]+)*\.inntegra\.com\.br\z/
  COMPANY = /\A[a-z0-9_]{2,40}\z/
  FIELD = /\A[A-Z][A-Za-z0-9]{1,60}\z/
  ENDPOINT = /\AUpdate[A-Za-z0-9]{2,60}\z/
  DATE_TYPES = %w[DataEntrada DataPrevisao DataEntrega].freeze
  # campo => endpoint confirmados pelo painel do ERP (Update<Campo>/{OS}, corpo { <Campo>, listaEmpresas, Empresa }).
  # SubStatus, Situacao (status) e Tecnico têm fluxo próprio (histórico/lista), fora daqui.
  CONFIRMED_FIELDS = {
    'Defeitos' => 'UpdateDefeitos', 'Observacoes' => 'UpdateObservacoes', 'Acessorios' => 'UpdateAcessorios',
    'DataPrevisao' => 'UpdateDataPrevisao', 'DataValidade' => 'UpdateDataValidade'
  }.freeze
  # tipo de cada campo para a tela saber o controle (o resto é texto)
  FIELD_KINDS = { 'DataPrevisao' => 'date', 'DataValidade' => 'date' }.freeze
  RESERVED_FIELDS = %w[SubStatus Situacao CodigoOS Empresa listaEmpresas].freeze
  MAX_FIELDS = 20
  MAX_SUBSTATUS = 60

  DEFAULTS = {
    'enabled' => false, 'base_url' => 'https://somos-backend.inntegra.com.br', 'companies' => [], 'device_id' => '',
    'lookback_days' => 180, 'forward_days' => 365, 'date_type' => 'DataEntrada', 'cache_seconds' => 120,
    'orders_enabled' => true, 'quotes_enabled' => true, 'quotes_days' => 120, 'quotes_cache_seconds' => 600,
    'write_enabled' => false, 'note_on_change' => true, 'erp_user_id' => '0', 'user_erp_ids' => {},
    'extra_fields' => [], 'substatus_options' => [], 'locked_statuses' => %w[FECHADA CANCELADA PERDIDA],
    # orçamento de peças e serviços (Outsider::Erp::Budget), gravado pelas funções do ERP (Outsider::Erp::QuoteCreator);
    # a gravação começa desligada. Serviço (sem NCM, que a função do ERP descarta) é gravado direto por padrão
    # (decisão do dono em 19/11/2026), até a Inntegra corrigir a função. Padrões do formulário (os textos de envio do
    # orçamento e da OS ficam em Outsider::Erp::SendTexts). Desconto acima do limite (% por linha e no total)
    # pede o código e a senha de quem tem a permissão de desconto do ERP (Outsider::Erp::DiscountPolicy); o ERP da Somos
    # não tem limite preenchido, então ele fica aqui (0 = qualquer desconto pede liberação).
    # Peça que a função descarta (sem NCM para a UF/gênero do cliente) também vai direto, sem imposto (24/11/2026: orçamento
    # é rascunho de venda; imposto conta na OS e no pedido). Gênero: sempre REVENDA (Outsider::Erp::BudgetForm::GENERO).
    'quote_write_enabled' => false, 'quote_forma_pagto' => 0, 'quote_tipo_frete' => 0, 'quote_genero_operacao' => 1,
    'quote_services_direct' => true, 'quote_parts_direct' => true, 'quote_discount_approval' => true,
    'quote_discount_line_max' => 0, 'quote_discount_total_max' => 0,
    'quote_prazo_entrega' => '', 'quote_validade' => '', 'quote_garantia' => '',
    'quote_reply_to' => '',
    # cadastro de cliente no ERP pela função do próprio Mais Prático (sp_CadastraCliente, Outsider::Erp::ClientRegistrar):
    # entra como pré-cadastro, que o escritório completa. Desligado por padrão.
    'client_write_enabled' => false
  }.merge(Outsider::Erp::SendTexts::DEFAULTS, NEXTCLOUD_DEFAULTS, COMPANY_NAMES_DEFAULTS, REPORTS_DEFAULTS).freeze
  # textos livres e o tamanho máximo: os do formulário do orçamento e os de envio (orçamento e OS, Outsider::Erp::SendTexts)
  TEXTS = { 'quote_prazo_entrega' => 255, 'quote_validade' => 255, 'quote_garantia' => 255 }.merge(Outsider::Erp::SendTexts::LIMITS).freeze

  class Invalid < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super(errors.join(', '))
    end
  end

  def initialize(account)
    @account = account
  end

  attr_reader :account

  def data
    @data ||= DEFAULTS.merge(@account.internal_attributes.to_h[KEY].to_h)
  end

  def enabled? = data['enabled'] == true && companies.any?
  # OS na tela (quadro, lista no contato, edição). Desligado, ficam só os orçamentos; o espelho das OS continua sendo
  # lido por trás só para achar o cliente do ERP ao vincular um contato (Outsider::Erp::ServiceOrders#customers)
  def orders_enabled? = enabled? && data['orders_enabled'] == true
  def write_enabled? = orders_enabled? && data['write_enabled'] == true
  def quotes_enabled? = enabled? && data['quotes_enabled'] == true
  def quote_write_enabled? = enabled? && data['quote_write_enabled'] == true
  def client_write_enabled? = enabled? && data['client_write_enabled'] == true
  def companies = Array(data['companies'])
  def base_url = data['base_url']
  def device_id = data['device_id'].to_s
  # situacoes terminais da OS (dados: FECHADA/CANCELADA/PERDIDA): gravar numa OS nesses status fica bloqueado
  def locked_statuses = Array(data['locked_statuses']).map { |s| s.to_s.strip.upcase }

  # campo do ERP => endpoint de gravação (os confirmados e os cadastrados pelo administrador)
  def writable_fields
    CONFIRMED_FIELDS.merge(Array(data['extra_fields']).to_h { |row| [row['field'], row['endpoint']] })
  end

  # idUsuario do ERP que vai no histórico do substatus: o da pessoa, senão o padrão da integração
  def erp_user_id_for(user)
    data['user_erp_ids'].to_h[user.id.to_s].presence || data['erp_user_id'].to_s
  end

  def as_json(*)
    # o x-device-id e a senha do Nextcloud não voltam para a tela, só se existem
    data.except('device_id', 'nextcloud_secret').merge(
      'device_id_set' => device_id.present?, 'nextcloud_password_set' => nextcloud_password.present?, 'confirmed_fields' => CONFIRMED_FIELDS,
      'field_kinds' => FIELD_KINDS, 'writable_fields' => writable_fields
    )
  end

  def update(params)
    params = params.to_h.deep_stringify_keys
    @errors = []
    parts = %i[clean_connection clean_display clean_cache clean_write clean_quote clean_client clean_nextcloud clean_company_names clean_reports]
    cleaned = parts.reduce(data) { |out, part| out.merge(send(part, params)) }
    raise Invalid, @errors if @errors.any?

    @account.with_lock do
      @account.update_columns(internal_attributes: @account.internal_attributes.merge(KEY => cleaned)) # rubocop:disable Rails/SkipsModelValidations
    end
    @data = nil
    self
  end

  private

  def flag(params, key) = params.fetch(key, data[key]) == true

  def clean_connection(params)
    {
      'enabled' => flag(params, 'enabled'), 'base_url' => clean_url(params.fetch('base_url', base_url)),
      'companies' => clean_companies(params.fetch('companies', companies)), 'device_id' => clean_device_id(params),
      'date_type' => DATE_TYPES.include?(params['date_type']) ? params['date_type'] : data['date_type']
    }
  end

  # o que aparece na tela: OS e/ou orçamentos
  def clean_display(params)
    { 'orders_enabled' => flag(params, 'orders_enabled'), 'quotes_enabled' => flag(params, 'quotes_enabled') }
  end

  def clean_cache(params)
    {
      'lookback_days' => clamp(params, 'lookback_days', 1, 730), 'forward_days' => clamp(params, 'forward_days', 0, 730),
      'cache_seconds' => clamp(params, 'cache_seconds', 30, 3600),
      'quotes_days' => clamp(params, 'quotes_days', 7, 730), 'quotes_cache_seconds' => clamp(params, 'quotes_cache_seconds', 60, 7200)
    }
  end

  def clean_write(params)
    {
      'write_enabled' => flag(params, 'write_enabled'), 'note_on_change' => flag(params, 'note_on_change'),
      'erp_user_id' => clean_erp_user(params.fetch('erp_user_id', data['erp_user_id'])),
      'user_erp_ids' => clean_user_ids(params.fetch('user_erp_ids', data['user_erp_ids'])),
      'extra_fields' => clean_fields(params.fetch('extra_fields', data['extra_fields'])),
      'substatus_options' => clean_substatus(params.fetch('substatus_options', data['substatus_options']))
    }
  end

  # orçamento: liga/desliga, padrões do formulário (forma de pagamento, frete, gênero, prazos) e textos de envio
  def clean_quote(params)
    {
      'quote_write_enabled' => flag(params, 'quote_write_enabled'), 'quote_services_direct' => flag(params, 'quote_services_direct'),
      'quote_forma_pagto' => clamp(params, 'quote_forma_pagto', 0, 999_999),
      'quote_tipo_frete' => clamp(params, 'quote_tipo_frete', 0, 9),
      'quote_genero_operacao' => Outsider::Erp::BudgetForm::GENERO, 'quote_parts_direct' => flag(params, 'quote_parts_direct'),
      'quote_discount_approval' => flag(params, 'quote_discount_approval'),
      'quote_discount_line_max' => clamp(params, 'quote_discount_line_max', 0, 100),
      'quote_discount_total_max' => clamp(params, 'quote_discount_total_max', 0, 100),
      'quote_reply_to' => clean_reply_to(params.fetch('quote_reply_to', data['quote_reply_to']))
    }.merge(TEXTS.to_h { |key, max| [key, params.fetch(key, data[key]).to_s.strip.first(max)] })
  end

  def clean_client(params)
    { 'client_write_enabled' => flag(params, 'client_write_enabled') }
  end

  def clean_reply_to(value)
    value = value.to_s.strip
    return value if value.empty? || value.match?(URI::MailTo::EMAIL_REGEXP)

    @errors << 'quote_reply_to'
    data['quote_reply_to'].to_s
  end

  def clean_url(value)
    uri = URI.parse(value.to_s.strip.chomp('/'))
    return uri.to_s if uri.is_a?(URI::HTTPS) && uri.host.to_s.downcase.match?(HOST) && uri.path.blank? && uri.port == 443

    @errors << 'base_url'
    base_url
  rescue URI::InvalidURIError
    @errors << 'base_url'
    base_url
  end

  # vazio mantém o que já estava; clear_device_id apaga
  def clean_device_id(params)
    return '' if params['clear_device_id'] == true

    value = params['device_id'].to_s.strip
    return device_id if value.blank?

    return value if value.match?(/\A[\x21-\x7e]{1,200}\z/)

    @errors << 'device_id'
    device_id
  end

  def clean_erp_user(value)
    value = value.to_s.strip
    return value if value.match?(/\A\d{1,9}\z/)

    @errors << 'erp_user_id'
    '0'
  end

  def clean_user_ids(map)
    map.to_h.each_with_object({}) do |(user_id, erp_id), out|
      next if erp_id.to_s.strip.blank?
      next @errors << 'user_erp_ids' unless erp_id.to_s.strip.match?(/\A\d{1,9}\z/) && @account.users.exists?(id: user_id.to_i)

      out[user_id.to_i.to_s] = erp_id.to_s.strip
    end
  end

  def clean_fields(rows)
    rows = field_rows(rows)
    valid = rows.select { |row| valid_field?(row) }.uniq { |row| row['field'] }
    @errors << 'extra_fields' if valid.size != rows.size || valid.size > MAX_FIELDS
    valid.first(MAX_FIELDS)
  end

  def field_rows(rows)
    Array(rows).map { |row| { 'field' => row['field'].to_s.strip, 'endpoint' => row['endpoint'].to_s.strip } }
               .reject { |row| row['field'].blank? && row['endpoint'].blank? }
  end

  # nome de campo e de endpoint no formato do ERP, sem tocar no substatus (fluxo próprio) nem nos confirmados
  def valid_field?(row)
    row['field'].match?(FIELD) && row['endpoint'].match?(ENDPOINT) && RESERVED_FIELDS.exclude?(row['field']) &&
      CONFIRMED_FIELDS.keys.exclude?(row['field']) && !row['endpoint'].start_with?('UpdateSubStatus')
  end

  def clean_substatus(list)
    Array(list).map { |item| item.to_s.squish.first(80) }.compact_blank.uniq.first(MAX_SUBSTATUS)
  end

  def clamp(params, key, min, max)
    params.fetch(key, data[key]).to_i.clamp(min, max)
  end
end
