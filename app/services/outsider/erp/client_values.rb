# OUTSIDER: os valores que vão para a função de cadastro do ERP, já no jeito da unidade (Outsider::Erp::ClientProfile):
# CPF/CNPJ e CEP com ou sem máscara, maiúsculas, TipoPessoa da unidade e cada texto cortado no tamanho do campo. A
# observação diz que o pré-cadastro veio do Chatwoot e por quem.
class Outsider::Erp::ClientValues
  def initialize(form, profile, key:, author:)
    @form = form
    @profile = profile
    @values = build(key, author)
  end

  def [](key) = @values[key]
  def to_h = @values

  private

  def build(key, author)
    values = @form.values.except('vendedor').to_h { |field, value| [field, cased(field, value)] }
    values.merge!('documento' => document, 'cep' => cep, 'observacoes' => note(values['observacoes'], author), 'chave' => key)
    values.to_h { |field, value| [field, cut(field, value)] }
          .merge('tipo' => @profile.person_code(@form.person), 'vendedor' => @form.values['vendedor'])
  end

  def cased(field, value)
    @profile.uppercase? && Outsider::Erp::ClientForm::UPPER.include?(field) ? value&.upcase : value
  end

  # com máscara só se a unidade usa e o campo cabe (senão só os caracteres)
  def document
    masked = @form.masked_document
    @profile.masked_document? && fits?('documento', masked) ? masked : @form.document
  end

  def cep
    masked = @form.masked_cep
    masked && @profile.masked_cep? && fits?('cep', masked) ? masked : @form.values['cep']
  end

  def note(text, author)
    day = Time.find_zone('America/Sao_Paulo').today.strftime('%d/%m/%Y')
    stamp = "Pré-cadastro feito no Chatwoot#{" por #{author.squish}" if author.present?} em #{day}."
    [stamp, text].compact_blank.join(' ')
  end

  def fits?(field, value)
    limit = @profile.limit(field)
    limit.nil? || value.length <= limit
  end

  # e-mail e documento cortados viram outro dado: nesses, passar do tamanho é erro (a chave só fica mais curta)
  def cut(field, value)
    return value unless value.is_a?(String)

    limit = @profile.limit(field)
    return value if limit.nil? || value.length <= limit
    raise Outsider::Erp::ClientRegistrar::Invalid.new('tamanho', [field]) if %w[documento email contato_email].include?(field)

    value.first(limit).strip
  end
end
