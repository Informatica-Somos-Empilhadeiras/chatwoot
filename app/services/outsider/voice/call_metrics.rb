# OUTSIDER: os indicadores de um conjunto de ligações (Entrega 24), usados pelo painel, pelas planilhas e pelo
# relatório em PDF.
#
# - taxa de atendimento: recebidas atendidas / recebidas;
# - taxa de contato: feitas que o cliente atendeu / feitas;
# - nível de serviço: recebidas atendidas em até SERVICE_SECONDS / recebidas (as perdidas contam contra);
# - TMA (tempo médio de conversa) e TME (tempo médio para atender as recebidas);
# - retorno: das perdidas do período, quantas já foram retornadas e em quanto tempo, em média.
# Taxa sem ligação para medir fica nil (a tela mostra "—").
class Outsider::Voice::CallMetrics
  SERVICE_SECONDS = 20
  TALK_BUCKETS = [60, 180, 300, 600, 1200].freeze
  WAIT_BUCKETS = [10, 20, 30, 60].freeze

  def initialize(calls)
    @calls = calls
  end

  def to_h
    counts.merge(rates).merge(times).merge(returns).merge(customers: customers)
  end

  def counts
    {
      total: @calls.size, inbound: inbound.size, outbound: outbound.size, internal: @calls.count(&:internal?),
      inbound_answered: inbound_answered.size, missed: inbound.count(&:missed?), outbound_answered: outbound.count(&:answered?),
      unanswered: outbound.count(&:unanswered?), busy: outbound.count(&:busy?), failed: outbound.count(&:failed?)
    }
  end

  # quantas conversas em cada faixa de duração (até 1 min, 1 a 3 min...) e de espera para atender
  def talk_buckets
    buckets(answered.map(&:talk_seconds), TALK_BUCKETS)
  end

  def wait_buckets
    buckets(waits, WAIT_BUCKETS)
  end

  private

  def inbound
    @inbound ||= @calls.select(&:inbound?)
  end

  def outbound
    @outbound ||= @calls.select(&:outbound?)
  end

  def answered
    @answered ||= @calls.select(&:answered?)
  end

  def inbound_answered
    @inbound_answered ||= inbound.select(&:answered?)
  end

  def waits
    @waits ||= inbound_answered.map { |call| [(call.answered_at - call.started_at).round, 0].max }
  end

  def rates
    {
      answer_rate: rate(inbound_answered.size, inbound.size),
      contact_rate: rate(outbound.count(&:answered?), outbound.size),
      service_level: rate(waits.count { |wait| wait <= SERVICE_SECONDS }, inbound.size)
    }
  end

  def times
    talks = answered.map(&:talk_seconds)
    { talk_seconds: talks.sum, average_talk: average(talks), longest_talk: talks.max || 0, average_answer: average(waits),
      longest_wait: waits.max || 0 }
  end

  def returns
    missed = inbound.select(&:missed?)
    returned = missed.select(&:returned_at)
    { returned: returned.size, return_rate: rate(returned.size, missed.size),
      average_return: average(returned.map { |call| (call.returned_at - call.started_at).round }) }
  end

  # clientes diferentes (pelo número) com quem houve ligação
  def customers
    @calls.reject(&:internal?).filter_map { |call| Outsider::Voice::PhoneNumber.digits(call.customer_number).last(10).presence }.uniq.size
  end

  def rate(part, whole)
    whole.zero? ? nil : (part * 100.0 / whole).round(1)
  end

  def average(values)
    values.empty? ? 0 : (values.sum.to_f / values.size).round
  end

  def buckets(values, limits)
    Array.new(limits.size + 1) do |index|
      low = index.zero? ? 0 : limits[index - 1]
      high = limits[index]
      { from: low, to: high, count: values.count { |value| value >= low && (high.nil? || value < high) } }
    end
  end
end
