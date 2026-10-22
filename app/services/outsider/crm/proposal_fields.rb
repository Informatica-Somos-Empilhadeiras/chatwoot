# OUTSIDER: campos automáticos dos textos da proposta ({cliente.empresa}, {proposta.validade}...). Usados
# no PDF e mostrados na tela de modelos. Campo desconhecido fica como está, para o erro aparecer no PDF.
class Outsider::Crm::ProposalFields
  MONTHS = %w[Janeiro Fevereiro Março Abril Maio Junho Julho Agosto Setembro Outubro Novembro Dezembro].freeze
  PATTERN = /\{([a-z_]+\.[a-z_]+)\}/

  def initialize(proposal, company)
    @proposal = proposal
    @company = company
  end

  def apply(text)
    text.to_s.gsub(PATTERN) { values.fetch(Regexp.last_match(1), Regexp.last_match(0)) }
  end

  def values
    @values ||= customer_values.merge(proposal_values).merge(company_values).merge(
      'maquina.nome' => main_item&.dig('details', 'title').presence || main_description,
      'maquina.marca' => main_item&.dig('details', 'brand').to_s,
      'vendedor.nome' => @proposal.signer['name'].to_s,
      'vendedor.cargo' => @proposal.signer['title'].to_s,
      'vendedor.telefone' => @proposal.signer['phone'].to_s
    )
  end

  # "Goiânia, 07 de Outubro de 2026"
  def date_line
    date = @proposal.issued_on || Time.zone.today
    [@company['city'].presence, "#{format('%02d', date.day)} de #{MONTHS[date.month - 1]} de #{date.year}"].compact.join(', ')
  end

  def self.validity(proposal)
    return '' if proposal.valid_until.blank? || proposal.issued_on.blank?

    days = (proposal.valid_until - proposal.issued_on).to_i
    days == 1 ? '1 DIA' : "#{days} DIAS"
  end

  def self.customer_address(customer)
    city = [customer['city'], customer['state']].compact_blank.join(' ')
    [customer['address'], [customer['district'], city].compact_blank.join(' - '), customer['zip'].presence && "CEP: #{customer['zip']}"]
      .compact_blank.join(', ')
  end

  private

  def customer_values
    customer = @proposal.customer
    {
      'cliente.empresa' => customer['company'], 'cliente.documento' => customer['document'],
      'cliente.ie' => customer['state_registration'], 'cliente.endereco' => customer['address'],
      'cliente.bairro' => customer['district'], 'cliente.cidade' => customer['city'], 'cliente.estado' => customer['state'],
      'cliente.cep' => customer['zip'], 'cliente.telefone' => customer['phone'], 'cliente.email' => customer['email'],
      'cliente.atencao' => customer['attention'], 'cliente.endereco_completo' => self.class.customer_address(customer)
    }.transform_values(&:to_s)
  end

  def proposal_values
    {
      'proposta.numero' => @proposal.number.to_s, 'proposta.titulo' => @proposal.title.to_s,
      'proposta.validade' => self.class.validity(@proposal), 'proposta.data' => date_line,
      'proposta.total' => ActiveSupport::NumberHelper.number_to_currency(@proposal.total_cents / 100.0, unit: 'R$ ', separator: ',',
                                                                                                        delimiter: '.')
    }
  end

  def company_values
    {
      'empresa.razao_social' => @company['legal_name'], 'empresa.nome_fantasia' => @company['trade_name'],
      'empresa.cnpj' => @company['cnpj'], 'empresa.endereco' => @company['address'].to_s.split("\n").map(&:strip).compact_blank.join(', '),
      'empresa.cidade' => @company['city'], 'empresa.email_documentos' => @company['documents_email']
    }.transform_values(&:to_s)
  end

  def main_item
    @main_item ||= @proposal.items.find { |item| item.details.present? }&.attributes
  end

  def main_description
    @proposal.items.first&.description.to_s
  end
end
