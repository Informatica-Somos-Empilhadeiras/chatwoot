# OUTSIDER: a chave do Google Maps que o navegador usa para o Street View e o mapa dos locais (Maps Embed API). Fica em
# accounts.internal_attributes (sem tabela). É uma chave de navegador: aparece na página para quem usa a conta, por isso
# o administrador a restringe no Google Cloud ao endereço do Chatwoot (referenciadores HTTP) e à Maps Embed API.
class Outsider::MapsSettings
  KEY = 'outsider_google_maps_key'.freeze
  MAP_ID = 'outsider_google_maps_map_id'.freeze
  FORMAT = /\A[A-Za-z0-9_-]{20,100}\z/
  # Map ID vetorial do Google Cloud (opcional): libera a Vista 3D (mapa inclinado e girável) no Mapa dos agendamentos
  MAP_ID_FORMAT = /\A[A-Za-z0-9_-]{4,64}\z/

  class Invalid < StandardError; end

  def initialize(account)
    @account = account
  end

  def key
    @account.internal_attributes[KEY].presence
  end

  def map_id
    @account.internal_attributes[MAP_ID].presence
  end

  # map_id: nil = não mexe
  def update(value, map_id: nil)
    value = value.to_s.strip
    raise Invalid, 'invalid_key' if value.present? && !value.match?(FORMAT)

    changes = { KEY => value.presence }
    unless map_id.nil?
      map_id = map_id.to_s.strip
      raise Invalid, 'invalid_map_id' if map_id.present? && !map_id.match?(MAP_ID_FORMAT)

      changes[MAP_ID] = map_id.presence
    end
    @account.with_lock do
      # update_columns para não esbarrar nas validações de outros campos da conta
      @account.update_columns(internal_attributes: @account.internal_attributes.merge(changes)) # rubocop:disable Rails/SkipsModelValidations
    end
    key
  end
end
