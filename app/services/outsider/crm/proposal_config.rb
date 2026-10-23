# OUTSIDER: configurações das propostas por conta, em accounts.internal_attributes (como as outras do CRM):
# próximo número, dados da empresa que emite (padrão e, se quiser, diferentes por unidade), assinatura de cada
# vendedor e quem vê as propostas de quem. Ficam fora do código porque o repositório é público.
#
# win_deal_on_accept: proposta aceita marca o negócio ligado como ganho (desligado de início)
# payment_options: opções de condição de pagamento que a proposta oferece (Entrega 19); até o
# administrador mudar, valem as DEFAULT_PAYMENT_OPTIONS
# send_message / email_subject: textos que abrem a janela de envio, com {contato}, {numero}, {titulo},
# {vendedor} e {empresa}; em branco vale o padrão do idioma da conta.
#
# access: { user_id => { 'view' => 'own' | 'users' | 'all', 'user_ids' => [...], 'catalog' => bool } }
# Administrador vê todas e mexe no catálogo sem precisar estar aqui.
class Outsider::Crm::ProposalConfig
  KEY = 'outsider_crm_proposals'.freeze
  COMPANY_KEYS = %w[legal_name trade_name cnpj address city documents_email bank_details].freeze
  SIGNATURE_KEYS = %w[title phone].freeze
  VIEWS = %w[own users all].freeze
  SEND_TEXT_KEYS = %w[send_message email_subject].freeze
  SEND_TEXT_LIMIT = 2_000
  DEFAULT_PAYMENT_OPTIONS = ['A VISTA', '30% + 06X NO BOLETO', 'CARTÃO DE CRÉDITO'].freeze
  MAX_PAYMENT_OPTIONS = 30
  PAYMENT_OPTION_LIMIT = 200

  class Invalid < StandardError; end

  def initialize(account)
    @account = account
  end

  def to_h
    @account.internal_attributes.fetch(KEY, {})
  end

  def next_number
    to_h.fetch('next_number', 1).to_i
  end

  # Dados da empresa para a proposta: os da unidade, completando com os padrão
  def company(unit_id = nil)
    default = blank_company.merge(to_h.fetch('company', {}).slice(*COMPANY_KEYS))
    unit = to_h.fetch('unit_companies', {}).fetch(unit_id.to_s, {}).slice(*COMPANY_KEYS).compact_blank
    default.merge(unit)
  end

  def unit_companies
    to_h.fetch('unit_companies', {})
  end

  def signature(user_id)
    SIGNATURE_KEYS.index_with('').merge(to_h.fetch('signatures', {}).fetch(user_id.to_s, {}).slice(*SIGNATURE_KEYS))
  end

  def access(user_id)
    rule = to_h.fetch('access', {}).fetch(user_id.to_s, {})
    { 'view' => VIEWS.include?(rule['view']) ? rule['view'] : 'own', 'user_ids' => Array(rule['user_ids']).map(&:to_i),
      'catalog' => rule['catalog'] == true }
  end

  def access_rules
    to_h.fetch('access', {})
  end

  def win_deal_on_accept?
    to_h['win_deal_on_accept'] == true
  end

  def payment_options
    to_h.fetch('payment_options', DEFAULT_PAYMENT_OPTIONS)
  end

  # Textos gravados (podem estar em branco) e os padrão, para a tela mostrar o que vale
  def send_texts
    SEND_TEXT_KEYS.index_with { |key| to_h[key].to_s }
  end

  def effective_send_texts
    SEND_TEXT_KEYS.index_with { |key| to_h[key].presence || I18n.t("outsider_crm.proposals.send.defaults.#{key}") }
  end

  # Só muda o que vier: próximo número, ganhar o negócio ao aceitar, os textos do envio e as opções de pagamento
  def update_general(values)
    values = values.to_h.stringify_keys
    changes = {}
    changes['next_number'] = valid_number(values['next_number']) if values.key?('next_number')
    changes['win_deal_on_accept'] = ActiveModel::Type::Boolean.new.cast(values['win_deal_on_accept']) || false if values.key?('win_deal_on_accept')
    SEND_TEXT_KEYS.each { |key| changes[key] = values[key].to_s.strip[0, SEND_TEXT_LIMIT] if values.key?(key) }
    changes['payment_options'] = valid_payment_options(values['payment_options']) if values.key?('payment_options')
    write { |data| data.merge(changes) }
  end

  # unit_id nil: dados padrão; com unidade, só os campos preenchidos valem para ela
  def update_company(values, unit_id: nil)
    company = values.to_h.stringify_keys.slice(*COMPANY_KEYS).transform_values { |value| value.to_s.strip[0, 2_000] }
    if unit_id.present?
      raise Invalid, 'unit' unless Outsider::Crm::BusinessUnit.exists?(account_id: @account.id, id: unit_id)

      write { |data| data.merge('unit_companies' => data.fetch('unit_companies', {}).merge(unit_id.to_s => company.compact_blank)) }
    else
      write { |data| data.merge('company' => company) }
    end
  end

  def update_signature(user_id, values)
    signature = values.to_h.stringify_keys.slice(*SIGNATURE_KEYS).transform_values { |value| value.to_s.strip[0, 120] }
    write { |data| data.merge('signatures' => data.fetch('signatures', {}).merge(user_id.to_s => signature)) }
  end

  def update_access(user_id, values)
    values = values.to_h.stringify_keys
    view = values['view'].to_s
    raise Invalid, 'view' unless VIEWS.include?(view)

    rule = { 'view' => view, 'user_ids' => view == 'users' ? access_ids(values['user_ids'], user_id) : [],
             'catalog' => ActiveModel::Type::Boolean.new.cast(values['catalog']) || false }
    write { |data| data.merge('access' => data.fetch('access', {}).merge(user_id.to_s => rule)) }
  end

  private

  def valid_number(value)
    number = Integer(value, exception: false)
    raise Invalid, 'next_number' unless number&.between?(1, 99_999_999)

    number
  end

  # Sem linhas vazias nem repetidas, na ordem em que vieram
  def valid_payment_options(list)
    options = Array(list).map { |option| option.to_s.squish }.compact_blank.uniq
    raise Invalid, 'payment_options' if options.size > MAX_PAYMENT_OPTIONS || options.any? { |option| option.length > PAYMENT_OPTION_LIMIT }

    options
  end

  # Pessoas da conta, sem a própria
  def access_ids(list, user_id)
    ids = Array(list).map { |id| Integer(id, exception: false) }
    raise Invalid, 'user_ids' if ids.include?(nil)

    @account.account_users.where(user_id: ids.uniq - [user_id.to_i]).pluck(:user_id).sort
  end

  def blank_company
    COMPANY_KEYS.index_with('')
  end

  def write
    @account.with_lock do
      attributes = @account.internal_attributes
      data = yield(attributes.fetch(KEY, {}))
      # update_columns para não esbarrar nas validações de outros campos da conta
      @account.update_columns(internal_attributes: attributes.merge(KEY => data)) # rubocop:disable Rails/SkipsModelValidations
    end
    to_h
  end
end
