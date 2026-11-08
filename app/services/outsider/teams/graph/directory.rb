# OUTSIDER: as equipes de que o colaborador participa no Teams e os canais de cada uma, para ele escolher o que trazer
# (Configurações > Microsoft Teams). Guardado 5 minutos para a tela abrir rápido.
class Outsider::Teams::Graph::Directory
  MAX_TEAMS = 60

  def initialize(link)
    @link = link
    @client = Outsider::Teams::Graph::Client.new(link)
  end

  # [{ team_id, team_name, channels: [{ channel_id, channel_name, membership }] }]
  def teams(refresh: false)
    key = "outsider_teams_directory:#{@link.id}"
    Rails.cache.delete(key) if refresh
    Rails.cache.fetch(key, expires_in: 5.minutes) do
      joined = Array(@client.get('/me/joinedTeams?$select=id,displayName')['value']).first(MAX_TEAMS)
      teams = joined.map { |team| { 'team_id' => team['id'], 'team_name' => team['displayName'], 'channels' => channels_of(team['id']) } }
      teams.sort_by { |team| team['team_name'].to_s.downcase }
    end
  end

  private

  def channels_of(team_id)
    channels = Array(@client.get("/teams/#{team_id}/channels?$select=id,displayName,membershipType")['value']).map do |channel|
      { 'channel_id' => channel['id'], 'channel_name' => channel['displayName'], 'membership' => channel['membershipType'] }
    end
    channels.sort_by { |channel| [channel['channel_name'].in?(%w[General Geral]) ? 0 : 1, channel['channel_name'].to_s.downcase] }
  end
end
