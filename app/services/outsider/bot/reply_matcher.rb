# OUTSIDER: entende a resposta do cliente a um menu do bot. Aceita, nesta ordem:
#   - a escolha da lista ou do botão do WhatsApp (a Evolution grava "*List Response:* ... _ID_: <id>";
#     o botão chega igual com a Evolution atualizada, ver evolution-botoes.patch)
#   - o número da opção ("2", "2️⃣", "opção 2")
#   - o texto da opção, sem diferença de acento nem maiúscula ("sim", "Não")
class Outsider::Bot::ReplyMatcher
  # a marcação do WhatsApp (*negrito*, _itálico_) pode vir em volta dos nomes: _ID_: opt_1
  ID_LINE = /(?:^|\n)[\W_]*ID[\W_]*:\s*(\S+)/i
  TITLE_LINE = /(?:^|\n)[\W_]*(?:Title|T[ií]tulo)[\W_]*:\s*([^\n]+)/i
  RESPONSE_HEADER = /\A[\W_]*(List|Button|Lista|Bot[aã]o)\s*(Response|Resposta)/i
  KEYCAPS = { '0️⃣' => '0', '1️⃣' => '1', '2️⃣' => '2', '3️⃣' => '3', '4️⃣' => '4', '5️⃣' => '5',
              '6️⃣' => '6', '7️⃣' => '7', '8️⃣' => '8', '9️⃣' => '9', '🔟' => '10' }.freeze

  def self.fold(text)
    ::Outsider::TextPattern.normalize(text).gsub(/[^[:alnum:]\s]/, ' ').squish
  end

  def initialize(options)
    @options = Array(options)
  end

  # devolve a opção escolhida ou nil
  def match(content)
    text = content.to_s.strip
    return if text.blank?

    by_response(text) || by_number(text) || by_label(text)
  end

  private

  def by_response(text)
    return unless text.match?(RESPONSE_HEADER) || text.match?(ID_LINE)

    id = unwrap(text[ID_LINE, 1])
    found = @options.find { |option| option['id'] == id } if id
    found || ((title = unwrap(text[TITLE_LINE, 1])) && by_label(title))
  end

  # tira só a marcação das pontas (o id da opção tem _ no meio: opt_rent)
  def unwrap(value)
    value&.strip&.gsub(/\A[*_~]+|[*_~]+\z/, '')
  end

  def by_number(text)
    plain = KEYCAPS.reduce(text) { |value, (cap, digit)| value.gsub(cap, digit) }
    number = plain[/\A\D{0,10}?(\d{1,2})\W*\z/, 1]
    number && @options[number.to_i - 1] if number.to_i.positive?
  end

  def by_label(text)
    folded = self.class.fold(text)
    return if folded.blank?

    @options.find { |option| self.class.fold(option['label']) == folded } ||
      @options.find { |option| (label = self.class.fold(option['label'])).present? && folded.split.include?(label) && label.split.size == 1 } ||
      @options.find { |option| (label = self.class.fold(option['label'])).length >= 4 && folded.include?(label) }
  end
end
