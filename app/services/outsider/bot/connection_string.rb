# OUTSIDER: lê a "connection string" de um banco PostgreSQL, do jeito que o Supabase, o Railway e o Neon
# mostram: postgresql://usuario:senha@host:5432/banco?sslmode=require. A senha pode ter @, : ou #: o
# servidor é o que vem depois do último @. Guarda o endereço sem usuário e senha (base_url) e devolve o
# resto separado (a senha vai criptografada para a conexão).
module Outsider::Bot::ConnectionString
  PATTERN = %r{\A(postgres(?:ql)?)://(?:([^:@/]*)(?::(.*))?@)?(\[[^\]]+\]|[^@/:?]+)(?::(\d{1,5}))?/([^?#]+)(?:\?([^#]*))?\z}m
  BASE = %r{\Apostgresql://(\[[^\]]+\]|[^@/:?]+):\d{1,5}/[^/?#]+\z}
  SSL_MODES = %w[disable allow prefer require verify-ca verify-full].freeze
  SSL_HOSTS = /(\.supabase\.(co|com)|\.neon\.tech|\.render\.com|\.aivencloud\.com)\z/

  module_function

  def parse(value)
    match = value.to_s.strip.match(PATTERN)
    return unless match

    _scheme, user, password, host, port, database, query = match.captures
    params = URI.decode_www_form(query.to_s).to_h
    sslmode = SSL_MODES.include?(params['sslmode']) ? params['sslmode'] : default_sslmode(host)
    { base_url: "postgresql://#{host}:#{port.presence || 5432}/#{decode(database)}", username: decode(user.to_s),
      password: decode(password.to_s), sslmode: sslmode }
  rescue ArgumentError
    nil
  end

  def valid_base?(value)
    value.to_s.match?(BASE)
  end

  # { host:, port:, dbname: } de um base_url já salvo
  def parts(base_url)
    match = base_url.to_s.match(%r{\Apostgresql://(\[[^\]]+\]|[^@/:?]+):(\d{1,5})/(.+)\z})
    match && { host: match[1].delete('[]'), port: match[2].to_i, dbname: match[3] }
  end

  def default_sslmode(host)
    host.to_s.match?(SSL_HOSTS) ? 'require' : 'prefer'
  end

  # %40 -> @ quando a senha veio codificada; "+" continua "+"
  def decode(text)
    text.match?(/%[0-9A-Fa-f]{2}/) ? URI.decode_uri_component(text) : text
  end
end
