# OUTSIDER: montagem SEGURA de literais SQL para as chamadas de função do ERP via query_execute. Responsabilidade única:
# transformar um valor Ruby num literal MySQL escapado, para nunca concatenar dado de cliente cru numa query. Não executa
# nada — só formata. Identificadores (nome do banco da unidade) só passam se baterem com o formato restrito das empresas.
module Outsider::Erp::Sql
  module_function

  IDENT = /\A[a-z0-9_]{2,40}\z/
  COLUMN = /\A[A-Za-z][A-Za-z0-9_]{0,63}\z/
  # escapes exigidos pelo MySQL dentro de aspas simples
  ESCAPES = { '\\' => '\\\\', "'" => "\\'", "\n" => '\\n', "\r" => '\\r', "\u0000" => '\\0', "\u001A" => '\\Z' }.freeze

  # nome de banco/unidade usado como prefixo da função (somosemp.sp_...). Só os já validados em Settings#companies.
  def ident(value)
    value = value.to_s
    raise ArgumentError, "identificador inválido: #{value}" unless value.match?(IDENT)

    value
  end

  # nome de coluna lido do information_schema (Outsider::Erp::Schema), entre crases; nada fora do formato passa
  def column(value)
    value = value.to_s
    raise ArgumentError, "coluna inválida: #{value}" unless value.match?(COLUMN)

    "`#{value}`"
  end

  # 'texto' escapado; nil/"" viram NULL
  def str(value)
    return 'NULL' if value.nil?

    value = value.to_s
    return 'NULL' if value.empty?

    "'#{value.gsub(/[\\'\n\r\u0000\u001A]/) { |char| ESCAPES[char] }}'"
  end

  def int(value)
    return 'NULL' if value.nil? || value.to_s.strip.empty?

    Integer(value).to_s
  rescue ArgumentError, TypeError
    'NULL'
  end

  # número decimal com ponto, sem notação científica; nil vira 0
  def dec(value)
    return '0' if value.nil? || value.to_s.strip.empty?

    BigDecimal(value.to_s).to_s('F')
  rescue ArgumentError, TypeError
    '0'
  end

  # 'YYYY-MM-DD' a partir de Date/Time/ISO; nil vira NULL
  def date(value)
    return 'NULL' if value.blank?

    str(value.respond_to?(:strftime) ? value.strftime('%Y-%m-%d') : Date.parse(value.to_s).strftime('%Y-%m-%d'))
  rescue ArgumentError, TypeError
    'NULL'
  end
end
