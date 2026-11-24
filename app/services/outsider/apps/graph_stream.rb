# OUTSIDER: lê um arquivo do Microsoft Graph aos pedaços com o token da pessoa (anexo de e-mail), sem guardar no disco nem
# na memória inteira. A Microsoft às vezes manda para um endereço temporário dela: segue sem o token.
class Outsider::Apps::GraphStream
  TIMEOUT = 60

  def initialize(client)
    @client = client
  end

  def get(path, &)
    url = "#{Outsider::Teams::Graph::Client::V1}#{path}"
    raise Outsider::Teams::Graph::Client::Error, 'host' unless Outsider::Teams::Graph::Client.graph_url?(url)

    response = HTTParty.get(url, headers: { 'Authorization' => "Bearer #{@client.token}" }, follow_redirects: false,
                                 stream_body: true, timeout: TIMEOUT) do |fragment|
      next if fragment.code.between?(300, 399) || fragment.code == 401
      raise Outsider::Teams::Graph::Client::Error.new("graph #{fragment.code}", fragment.code) unless fragment.code.between?(200, 299)

      yield fragment.to_s
    end
    follow(response, &)
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
    raise Outsider::Teams::Graph::Client::Error, e.message.first(200)
  end

  private

  def follow(response, &)
    return Outsider::Teams::Graph::Files.stream(response.headers['location'].to_s, &) if response.code.between?(300, 399)
    raise Outsider::Teams::Graph::Client::Error.new("graph #{response.code}", response.code) unless response.code.between?(200, 299)
  end
end
