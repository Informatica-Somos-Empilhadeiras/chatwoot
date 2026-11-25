# OUTSIDER: aviso das notas fiscais (NF-e e NFS-e) que ainda não foram para a nuvem (o Nextcloud onde o Fiscal guarda os
# PDFs; Outsider::Erp::NextcloudInvoices acha o arquivo). Tudo no Redis, sem tabela:
# - achada: a nota sai da verificação para sempre (o hash "ok");
# - não achada: fica no hash "falta" com a hora da última busca e volta a ser buscada de tempos em tempos;
# - nota marcada como achada que falhou ao abrir: não muda na hora. Fica "em dúvida" e é buscada de novo uma vez,
#   RECHECK_DELAY depois (Outsider::Erp::InvoiceCloudJob); só volta a "falta" se a segunda busca também não achar.
#   Erro de conexão com o Nextcloud nunca conta como "não está lá".
# Baixo consumo: o passe periódico (a cada 30 min) olha só as notas dos últimos DAYS dias, no máximo PER_RUN buscas por
# passe, cada nota no máximo a cada RETRY; a tela pede o estado das linhas que mostra e busca na hora só até
# ON_DEMAND das que nunca foram buscadas.
class Outsider::Erp::InvoiceCloud
  KINDS = %w[invoices service_invoices].freeze
  DAYS = 45
  PER_RUN = 30
  ON_DEMAND = 8
  RETRY = 2.hours
  RECHECK_DELAY = 10.minutes
  MAX_KEYS = 100
  # a nota emitida e não cancelada/inutilizada é a que precisa estar na nuvem
  SKIP_STATUS = /CANCEL|INUTIL|DENEG|REJEIT/i

  def initialize(account)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
  end

  def enabled? = @settings.enabled? && @settings.nextcloud_enabled?

  # keys: ["invoices:somosemp:123", ...] => { key => 'ok' | 'missing' | 'unknown' }; busca na hora até ON_DEMAND nunca vistas
  def statuses(keys)
    keys = Array(keys).map(&:to_s).select { |key| valid_key?(key) }.uniq.first(MAX_KEYS)
    return {} if keys.empty?

    found = values(ok_key, keys)
    missing = values(missing_key, keys)
    budget = ON_DEMAND
    keys.index_with do |key|
      next 'ok' if found[key]
      next 'missing' if missing[key]
      next 'unknown' if budget <= 0

      budget -= 1
      check(key) || 'unknown'
    end
  end

  # busca no Nextcloud e grava o resultado; nil se o Nextcloud/ERP não respondeu
  def check(key)
    kind, company, number = key.split(':')
    href = nextcloud.locate(company, number, kind)
    href ? mark_ok(key) : mark_missing(key)
  rescue Outsider::Erp::NextcloudInvoices::NotFound
    # nota sem número da prefeitura (NFS-e não emitida) ou fora do ERP: não é aviso de nuvem
    nil
  rescue Outsider::Erp::NextcloudInvoices::Error, Outsider::Erp::Client::Error => e
    Rails.logger.info("[Outsider::Erp] nuvem das notas #{key}: #{e.message}")
    nil
  end

  # a pessoa abriu a nota e o arquivo veio: sai da verificação
  def opened(kind, company, number) = mark_ok(key_for(kind, company, number))

  # a pessoa abriu e o arquivo não veio. Nunca vista ou já em falta: falta. Marcada como achada: busca de novo mais tarde
  def open_failed(kind, company, number)
    key = key_for(kind, company, number)
    return mark_missing(key) unless redis { |conn| conn.hget(ok_key, key) }

    Outsider::Erp::InvoiceCloudJob.set(wait: RECHECK_DELAY).perform_later(@account.id, key)
    'ok'
  end

  # segunda via de uma nota que falhou ao abrir: só tira do "ok" se esta busca também não achar
  def recheck(key)
    return unless valid_key?(key)

    kind, company, number = key.split(':')
    return if nextcloud.locate(company, number, kind)

    redis { |conn| conn.hdel(ok_key, key) }
    mark_missing(key)
  rescue Outsider::Erp::NextcloudInvoices::NotFound, Outsider::Erp::NextcloudInvoices::Error, Outsider::Erp::Client::Error
    nil
  end

  # passe periódico: notas recentes que ainda não foram achadas, as mais antigas na fila primeiro
  def sweep
    return 0 unless enabled?

    found = redis { |conn| conn.hgetall(ok_key) }
    missing = redis { |conn| conn.hgetall(missing_key) }
    due = recent_keys.reject { |key| found[key] }.select { |key| missing[key].to_i < RETRY.ago.to_i }
    due = due.sort_by { |key| missing[key].to_i }.first(PER_RUN)
    due.each { |key| check(key) }
    due.size
  end

  private

  def nextcloud = @nextcloud ||= Outsider::Erp::NextcloudInvoices.new(@account)
  def client = @client ||= Outsider::Erp::Client.new(@settings)
  def schema = @schema ||= Outsider::Erp::Schema.new(@account, client: client)

  # o mesmo Redis do Redis::Alfred (que não traz hdel/hgetall)
  def redis(&) = $alfred.with(&) # rubocop:disable Style/GlobalVars

  def ok_key = "outsider:erp:nf_nuvem:#{@account.id}:ok"
  def missing_key = "outsider:erp:nf_nuvem:#{@account.id}:falta"
  def key_for(kind, company, number) = "#{kind}:#{company}:#{number.to_i}"

  def valid_key?(key)
    kind, company, number = key.to_s.split(':')
    KINDS.include?(kind) && @settings.companies.include?(company) && number.to_i.positive? && key == key_for(kind, company, number)
  end

  def values(hash, keys)
    keys.zip(redis { |conn| conn.hmget(hash, *keys) }).to_h
  end

  def mark_ok(key)
    redis do |conn|
      conn.hset(ok_key, key, Time.current.to_i)
      conn.hdel(missing_key, key)
    end
    'ok'
  end

  def mark_missing(key)
    redis { |conn| conn.hset(missing_key, key, Time.current.to_i) }
    'missing'
  end

  # as chaves das notas emitidas nos últimos DAYS dias, de cada unidade e tipo (uma consulta por unidade e tipo)
  def recent_keys
    @settings.companies.flat_map do |company|
      KINDS.flat_map { |kind| recent(kind, company) }
    end
  end

  def recent(kind, company)
    definition = Outsider::Erp::Records::Kind.for(kind, @settings)
    columns = definition.columns
    key = schema.pick(company, definition.table, columns[:numero])
    date = schema.pick(company, definition.table, columns[:data])
    return [] unless key && date

    status = schema.pick(company, definition.table, columns[:status])
    db = Outsider::Erp::Sql.ident(company)
    sql = "SELECT N.#{Outsider::Erp::Sql.column(key)} AS chave, #{status ? "N.#{Outsider::Erp::Sql.column(status)}" : 'NULL'} AS status " \
          "FROM #{db}.#{definition.table} N WHERE N.#{Outsider::Erp::Sql.column(date)} >= " \
          "#{Outsider::Erp::Sql.str(DAYS.days.ago.to_date.iso8601)} ORDER BY N.#{Outsider::Erp::Sql.column(date)} DESC LIMIT 2000"
    client.query_execute(sql).grep(Hash).reject { |row| row['status'].to_s.match?(SKIP_STATUS) }
          .filter_map { |row| row['chave'].to_i.positive? ? key_for(kind, company, row['chave']) : nil }
  rescue Outsider::Erp::Client::Error, ArgumentError => e
    Rails.logger.info("[Outsider::Erp] nuvem das notas, lista #{company}/#{kind}: #{e.message}")
    []
  end
end
