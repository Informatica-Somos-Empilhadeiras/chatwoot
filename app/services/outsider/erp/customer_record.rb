# OUTSIDER: o cadastro de um cliente do ERP para o PDF do orçamento (nome, CPF/CNPJ, IE, endereço, telefone, e-mail).
# Só leitura, filtrado pelo banco da unidade e pelo código; as colunas vêm do Outsider::Erp::Schema (as que existirem).
class Outsider::Erp::CustomerRecord
  S = Outsider::Erp::Sql
  FIELDS = {
    'nome' => %w[Nome RazaoSocial], 'fantasia' => %w[Apelido Fantasia NomeFantasia], 'documento' => %w[CPF_CNPJ], 'ie' => %w[RGIE IE],
    'endereco' => %w[Endereco], 'numero' => %w[Numero], 'complemento' => %w[Complemento], 'bairro' => %w[Bairro],
    'cidade' => %w[Cidade], 'uf' => %w[UF], 'cep' => %w[cep CEP], 'fone' => %w[TelResidencia Telefone Fone],
    'celular' => %w[Celular], 'email' => %w[email Email]
  }.freeze

  def initialize(account, client:)
    @account = account
    @client = client
    @schema = Outsider::Erp::Schema.new(account, client: client)
  end

  def find(company, code)
    return {} unless code.to_i.positive?

    sql = "SELECT C.CodigoCliente AS codigo, #{@schema.select_list(company, 'clientes', 'C', FIELDS)} " \
          "FROM #{S.ident(company)}.clientes C WHERE C.CodigoCliente = #{S.int(code)}"
    row = @client.query_execute(sql).grep(Hash).first.to_h
    row.transform_values { |value| value.is_a?(String) ? value.squish : value }
  end

  # e-mails do cadastro (o campo pode ter vários, separados por ; ou ,)
  def self.emails(record)
    record['email'].to_s.split(/[;,\s]+/).grep(URI::MailTo::EMAIL_REGEXP)
  end
end
