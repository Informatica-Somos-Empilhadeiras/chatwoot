# OUTSIDER: o produto do ERP por inteiro para a aba Produtos (só consulta): o cabeçalho como na lista do orçamento
# (Outsider::Erp::Catalog), a descrição técnica e todos os outros campos preenchidos da tabela produtos, com o nome da
# coluna como rótulo. Custo, lucro, margem e comissão ficam de fora: a aba é para quem vende.
class Outsider::Erp::ProductDetail
  class NotFound < StandardError; end

  S = Outsider::Erp::Sql
  HIDDEN = /custo|lucro|margem|markup|comiss|senha/i
  # o que já está no cabeçalho (descrição, preço, unidade, estoque...) e a descrição técnica, que tem lugar próprio
  SKIP = (%w[CodigoProduto DescrTec] + Outsider::Erp::Catalog::DESCRIPTION + Outsider::Erp::Catalog::FIELDS.values.flatten).map(&:downcase).freeze
  MAX_TEXT = 300

  def initialize(account)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
    @client = Outsider::Erp::Client.new(@settings)
  end

  # { 'produto' => {...}, 'tecnica' => '...', 'campos' => [[rótulo, valor], ...] }
  def build(company, code)
    code = Integer(code.to_s, 10)
    catalog = Outsider::Erp::Catalog.new(@account)
    product = catalog.product(company, code) || raise(NotFound)
    { 'produto' => product, 'tecnica' => catalog.technical(company, code), 'campos' => fields(company, code) }
  end

  private

  def fields(company, code)
    sql = "SELECT P.* FROM #{S.ident(company)}.produtos P WHERE P.CodigoProduto = #{S.int(code)}"
    row = @client.query_execute(sql).grep(Hash).first.to_h
    row.filter_map { |name, value| [name.to_s.underscore.humanize, shown(value)] if visible?(name.to_s, value) }
  end

  # sem os ocultos, os vazios, os zerados e o que não é texto legível (imagem guardada na tabela, por exemplo)
  def visible?(name, value)
    return false if SKIP.include?(name.downcase) || name.match?(HIDDEN) || value.nil? || value == false

    readable?(value.to_s)
  end

  def readable?(text) = text.valid_encoding? && text.bytesize <= 2_000 && text.strip.present? && !text.strip.match?(/\A0+([.,]0+)?\z/)

  # data do ERP vira dd/mm/aaaa; número com casas decimais, com vírgula; texto longo é cortado
  def shown(value)
    text = value.to_s.strip
    return Time.zone.parse(text).strftime('%d/%m/%Y') if text.match?(/\A\d{4}-\d{2}-\d{2}T/)
    return format('%.2f', value).tr('.', ',') if value.is_a?(Float)

    text.truncate(MAX_TEXT)
  end
end
