# OUTSIDER: "Todos os canais" do Conectar meu Teams. Lê as equipes e canais da pessoa na Microsoft e deixa a lista de
# canais igual a eles, menos os que ela desmarcou (hidden_channels). Canal novo entra sozinho; canal apagado ou de equipe
# que a pessoa saiu, sai. Roda ao salvar e de hora em hora (Outsider::Teams::Graph::RenewJob).
class Outsider::Teams::Graph::AutoChannels
  MAX_CHANNELS = 100

  def initialize(link)
    @link = link
  end

  # true quando a lista mudou
  def refresh!(refresh_directory: true)
    return false unless @link.all_channels

    hidden = Array(@link.hidden_channels).map { |item| key(item) }
    wanted = available(refresh_directory: refresh_directory).reject { |channel| hidden.include?(key(channel)) }.first(MAX_CHANNELS)
    return false if wanted.map { |channel| key(channel) }.sort == @link.channel_list.map { |channel| key(channel) }.sort

    @link.update!(channels: wanted)
    true
  end

  def available(refresh_directory: false)
    Outsider::Teams::Graph::Directory.new(@link).teams(refresh: refresh_directory).flat_map do |team|
      team['channels'].map do |channel|
        { 'team_id' => team['team_id'], 'team_name' => team['team_name'], 'channel_id' => channel['channel_id'],
          'channel_name' => channel['channel_name'] }
      end
    end
  end

  private

  def key(item)
    "#{item['team_id']}|#{item['channel_id']}"
  end
end
