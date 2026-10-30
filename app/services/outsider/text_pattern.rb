# OUTSIDER: transforma o que a pessoa digitou em expressões regulares sem diferença de acento nem
# de maiúsculas ("joao" acha "João"). O Postgres usa os índices trigram (pg_trgm) com `~*`, então a
# busca não lê a tabela inteira: só as linhas que têm os trigramas da palavra.
# Palavras com menos de 3 letras não têm trigrama: sozinhas, elas não usam o índice.
module Outsider::TextPattern
  ACCENTS = 'áàâãäåéèêëíìîïóòôõöúùûüýÿçñÁÀÂÃÄÅÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÝÇÑ'.freeze
  PLAIN = 'aaaaaaeeeeiiiiooooouuuuyycnaaaaaaeeeeiiiiooooouuuuycn'.freeze
  # letra sem acento -> todas as formas dela ("a" -> "aáàâãäåÁÀÂÃÄÅ")
  VARIANTS = ACCENTS.each_char.with_index.each_with_object({}) do |(accented, index), variants|
    plain = PLAIN[index]
    variants[plain] = (variants[plain] || plain.dup) << accented
  end.transform_values(&:freeze).freeze
  TRIGRAM_LENGTH = 3

  module_function

  def normalize(text)
    text.to_s.tr(ACCENTS, PLAIN).downcase
  end

  def terms(text, min_length: 2, limit: 8)
    normalize(text).split.select { |term| term.length >= min_length }.uniq.first(limit)
  end

  def pattern_for(term)
    term.each_char.map do |char|
      if VARIANTS[char] then "[#{VARIANTS[char]}]"
      elsif char.match?(/[[:alnum:]]/) then char
      else
        "\\#{char}"
      end
    end.join
  end

  def indexable?(terms)
    terms.any? { |term| term.length >= TRIGRAM_LENGTH }
  end
end
