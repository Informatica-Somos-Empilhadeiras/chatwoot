# OUTSIDER: o bloco Banco de dados do bot fala direto com um PostgreSQL (Supabase, Railway, Neon, Render ou
# um servidor da empresa) por uma conexão do tipo postgres.
#   - abre a conexão só para a consulta e fecha logo depois (nada fica aberto parado)
#   - sem "permite alterar dados", tudo roda numa transação somente leitura: INSERT, UPDATE e DELETE são
#     recusados pelo próprio banco
#   - os valores das {{variáveis}} vão como parâmetros ($1, $2), nunca colados no SQL
#     (Outsider::Bot::Template#render_sql), então o que o cliente digita não vira comando
#   - uma consulta por vez (o PostgreSQL recusa vários comandos com parâmetros), tempo limite da conexão e
#     linhas lidas uma a uma: passou do limite, as demais são descartadas sem encher a memória
class Outsider::Bot::Integrations::Postgres
  Http = Outsider::Bot::Integrations::Http
  Result = Struct.new(:rows, :affected, :duration_ms, keyword_init: true)
  CONNECT_TIMEOUT = 5
  MAX_ROWS = 100
  MAX_CELL = 10_000
  ERRORS = {
    'PG::QueryCanceled' => 'timeout', 'PG::ReadOnlySqlTransaction' => 'write_not_allowed', 'PG::InsufficientPrivilege' => 'forbidden',
    'PG::ConnectionBad' => 'connection_failed', 'PG::UnableToSend' => 'connection_failed'
  }.freeze

  # read_only: o Testar do editor roda só leitura até o administrador confirmar
  def initialize(connection, read_only: false)
    raise Http::Error, 'not_postgres' unless connection&.postgres?

    @connection = connection
    @read_only = read_only || !connection.allow_write
  end

  def query(sql, params = [], limit: 1)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rows, affected = with_transaction { |pg| stream(pg, sql, params, limit.to_i.clamp(1, MAX_ROWS)) }
    Result.new(rows: rows, affected: affected, duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
  end

  def test
    result = query('SELECT current_database() AS banco, current_user AS usuario, version() AS versao')
    row = result.rows.first.to_h
    { 'database' => row['banco'], 'user' => row['usuario'], 'version' => row['versao'].to_s.split(' on ').first, 'duration_ms' => result.duration_ms }
  end

  private

  def with_transaction
    pg = PG::Connection.new(conninfo)
    pg.exec(@read_only ? 'BEGIN READ ONLY' : 'BEGIN')
    pg.exec("SET LOCAL statement_timeout = #{@connection.timeout_seconds.to_i.clamp(1, 30) * 1000}")
    result = yield pg
    pg.exec(@read_only ? 'ROLLBACK' : 'COMMIT')
    result
  rescue PG::Error => e
    raise Http::Error.new(ERRORS[e.class.name] || (e.is_a?(PG::ConnectionBad) ? 'connection_failed' : 'sql_error'), e.message.to_s.squish.first(300))
  ensure
    pg&.close
  end

  def stream(conn, sql, params, limit)
    conn.send_query_params(sql, params)
    conn.set_single_row_mode
    rows = []
    affected = 0
    while (result = conn.get_result)
      begin
        result.check
        if result.result_status == PG::PGRES_SINGLE_TUPLE
          rows << row(result) if rows.size < limit
        else
          affected = result.cmd_tuples.to_i
        end
      ensure
        result.clear
      end
    end
    [rows, affected]
  end

  def row(result)
    result.fields.each_with_index.to_h { |name, index| [name, cast(result.getvalue(0, index), result.ftype(index))] }
  end

  def cast(value, oid)
    return if value.nil?

    case oid
    when 16 then value == 't'
    when 20, 21, 23 then value.to_i
    when 700, 701 then value.to_f
    when 114, 3802 then parse_json(value)
    else value.to_s.first(MAX_CELL)
    end
  end

  def parse_json(value)
    JSON.parse(value)
  rescue JSON::ParserError
    value
  end

  def conninfo
    parts = Outsider::Bot::ConnectionString.parts(@connection.base_url) || raise(Http::Error, 'invalid_connection')
    password = @connection.secret('password') || raise(Http::Error, 'missing_secret')
    { host: parts[:host], port: parts[:port], dbname: parts[:dbname], user: @connection.settings['username'].to_s, password: password,
      sslmode: @connection.settings['sslmode'].presence || 'prefer', connect_timeout: CONNECT_TIMEOUT, application_name: 'chatwoot-bot' }
  end
end
