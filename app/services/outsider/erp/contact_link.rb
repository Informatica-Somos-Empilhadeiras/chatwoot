# OUTSIDER: de quais clientes do ERP um contato do Chatwoot é (empresa + CodigoCliente; a lista de OS do ERP não traz
# CNPJ nem telefone, então o vínculo é feito uma vez pelo agente). Fica em contacts.additional_attributes, sem migração;
# um contato pode ser cliente em mais de uma empresa do grupo.
class Outsider::Erp::ContactLink
  KEY = 'outsider_erp_clients'.freeze
  MAX = 10

  class Invalid < StandardError; end

  def initialize(contact)
    @contact = contact
  end

  def links
    Array(@contact.additional_attributes.to_h[KEY]).grep(Hash)
  end

  def add(company:, code:, name:, settings:)
    raise Invalid, 'company' unless settings.companies.include?(company.to_s)
    raise Invalid, 'code' unless code.to_s.match?(/\A\d{1,9}\z/)

    row = { 'empresa' => company.to_s, 'codigo' => code.to_i, 'nome' => name.to_s.squish.first(120) }
    store((links.reject { |link| same?(link, row) } + [row]).last(MAX))
  end

  def remove(company:, code:)
    store(links.reject { |link| same?(link, 'empresa' => company.to_s, 'codigo' => code.to_i) })
  end

  private

  def same?(link, other)
    link['empresa'] == other['empresa'] && link['codigo'].to_i == other['codigo'].to_i
  end

  # só a chave do vínculo (jsonb_set): não regrava o resto do contato nem dispara os avisos de contato alterado
  def store(list)
    Contact.where(id: @contact.id).update_all( # rubocop:disable Rails/SkipsModelValidations
      ["additional_attributes = jsonb_set(COALESCE(additional_attributes, '{}'::jsonb), '{#{KEY}}', ?::jsonb)", list.to_json]
    )
    @contact.reload
    links
  end
end
