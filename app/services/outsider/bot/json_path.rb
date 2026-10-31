# OUTSIDER: lê um campo dentro do resultado de um bloco (resposta de API, linha de planilha, documento).
#   pedido.status            campo
#   pedido.itens.0.nome      item da lista pela posição (também itens[0].nome)
#   pedido.itens.nome        o campo de cada item da lista
#   pedido.itens.quantidade  quantos itens a lista tem (também .tamanho e .length)
# O nome do campo não diferencia maiúscula de minúscula quando o exato não existe.
module Outsider::Bot::JsonPath
  SEGMENTS = /\[(\d+|\*)\]|([^.\[\]]+)/
  COUNT = %w[quantidade tamanho length count].freeze

  module_function

  def segments(path)
    path.to_s.scan(SEGMENTS).map { |index, key| index || key }
  end

  def dig(data, path)
    segments(path).reduce(data) do |current, key|
      return nil if current.nil?

      step(current, key)
    end
  end

  def step(current, key)
    case current
    when Array then array_step(current, key)
    when Hash then hash_step(current, key)
    end
  end

  def array_step(list, key)
    return list if key == '*'
    return list.size if COUNT.include?(key.downcase)
    return list[key.to_i] if key.match?(/\A-?\d+\z/)

    values = list.filter_map { |item| hash_step(item, key) if item.is_a?(Hash) }
    values.presence
  end

  def hash_step(hash, key)
    return hash[key] if hash.key?(key)

    found = hash.keys.find { |item| item.to_s.casecmp?(key) }
    found.nil? ? nil : hash[found]
  end
end
