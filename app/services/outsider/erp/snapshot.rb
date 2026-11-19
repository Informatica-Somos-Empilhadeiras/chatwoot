# OUTSIDER: cópia curta, no Redis, do que a API do ERP devolveu (as OS ou os orçamentos de todas as empresas). Espelha, não
# guarda: nada vai para o banco do Chatwoot e a cópia some sozinha em um dia.
#
# Para não pesar no ERP nem no Chatwoot:
# - dentro do tempo de cache (Configurações) todo mundo lê a mesma cópia: N painéis abertos = 1 chamada ao ERP;
# - passou do tempo: quem pediu recebe a cópia velha na hora e a busca nova vai para o Sidekiq (RefreshJob);
# - uma busca por vez (trava no Redis); quem chega sem cópia nenhuma espera a busca que já está andando;
# - o ERP fora do ar: continua valendo a última cópia (com o aviso de quando ela é), até um dia.
class Outsider::Erp::Snapshot
  class Loading < StandardError; end

  KEEP = 1.day
  LOCK_TTL = 90
  WAIT = 9
  SYNC_READ_TIMEOUT = 9

  # sync: false (orçamentos, uma chamada por empresa) nunca busca dentro da requisição: sem cópia, pede ao Sidekiq e a
  # tela tenta de novo em alguns segundos (Loading)
  def initialize(account, name, ttl:, loader:, sync: true)
    @account = account
    @name = name
    @ttl = ttl
    @loader = loader
    @sync = sync
  end

  # { 'at' => epoch, 'items' => [...], 'stale' => bool }
  def fetch
    snapshot = read
    return snapshot.merge('stale' => false) if snapshot && fresh?(snapshot)
    return refresh_later && snapshot.merge('stale' => true) if snapshot

    load_missing
  end

  # Sidekiq (Outsider::Erp::RefreshJob)
  def refresh!(read_timeout: Outsider::Erp::Client::READ_TIMEOUT)
    with_lock { write(@loader.call(read_timeout)) }
  end

  # depois de gravar no ERP: a cópia já mostra o valor novo, sem esperar a próxima busca
  def patch
    snapshot = read
    return unless snapshot

    items = snapshot['items'].map { |item| yield(item) || item }
    Redis::Alfred.set(key, Zlib.gzip(snapshot.merge('items' => items).to_json), ex: KEEP.to_i)
  end

  def read
    raw = Redis::Alfred.get(key)
    raw && JSON.parse(Zlib.gunzip(raw))
  end

  def clear
    Redis::Alfred.delete(key)
  end

  private

  def key = "outsider_erp:#{@account.id}:#{@name}"
  def lock_key = "#{key}:lock"

  def fresh?(snapshot)
    Time.current.to_i - snapshot['at'].to_i < @ttl
  end

  def refresh_later
    Outsider::Erp::RefreshJob.perform_later(@account.id, @name) unless Redis::Alfred.exists?(lock_key)
    true
  end

  def load_missing
    raise Loading unless @sync && (snapshot = load_now || wait_for_other)

    snapshot
  ensure
    refresh_later unless @sync
  end

  def load_now
    snapshot = refresh!(read_timeout: SYNC_READ_TIMEOUT)
    snapshot&.merge('stale' => false)
  rescue Outsider::Erp::Client::Error => e
    # demorou mais que a tela pode esperar: o Sidekiq tenta com mais tempo e a próxima abertura já acha a cópia
    Outsider::Erp::RefreshJob.perform_later(@account.id, @name) if e.message.include?('Timeout')
    raise
  end

  def wait_for_other
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      sleep 0.5
      snapshot = read
      return snapshot.merge('stale' => false) if snapshot
      break unless Redis::Alfred.exists?(lock_key)
    end
    nil
  end

  # nil quando outra busca já está andando
  def with_lock
    token = SecureRandom.hex(8)
    return unless Redis::Alfred.set(lock_key, token, nx: true, ex: LOCK_TTL)

    begin
      yield
    ensure
      Redis::Alfred.delete_if_equals(lock_key, token)
    end
  end

  def write(items)
    snapshot = { 'at' => Time.current.to_i, 'items' => items }
    Redis::Alfred.set(key, Zlib.gzip(snapshot.to_json), ex: KEEP.to_i)
    snapshot
  end
end
