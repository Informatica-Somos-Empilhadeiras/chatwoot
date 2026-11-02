# OUTSIDER: os áudios das URAs na central (Entrega 26). Cada fala de bloco (texto ou áudio enviado) tem um nome
# fixo tirado do conteúdo: mudou o texto, muda o nome. A central busca a lista a cada 30 s (manifest), baixa ou
# gera só o que ainda não tem e guarda como outsider/<nome> (8 kHz, o formato do telefone). O plano de discagem
# toca pelo nome (sound).
#
# Linhas da lista: "nome|audio" (a central baixa em /prompt: o áudio enviado ou o texto lido pela OpenAI) ou
# "nome|tts|<texto em base64>" (sem a OpenAI: a própria central lê o texto).
class Outsider::Voice::IvrPrompts
  NAME = /\A[a-f0-9]{20}\z/
  DEFAULT_VOICE = Outsider::Voice::IvrGraph::VOICES.first

  def initialize(account)
    @account = account
    @speech = Outsider::Voice::Speech.new(account)
  end

  # "outsider/<nome>", ou nil para fala vazia
  def sound(flow, prompt)
    name = name_for(flow, prompt)
    name && "outsider/#{name}"
  end

  def manifest
    entries.map do |name, source|
      source[:text] && !@speech.available? ? "#{name}|tts|#{Base64.strict_encode64(source[:text])}" : "#{name}|audio"
    end.join("\n")
  end

  # [conteúdo, tipo] do áudio pedido pela central, ou nil
  def fetch(name)
    source = name.to_s.match?(NAME) && entries[name]
    return unless source
    return [source[:blob].download, source[:blob].content_type] if source[:blob]

    @speech.synthesize(source[:text], source[:voice]) if @speech.available?
  end

  private

  def name_for(flow, prompt)
    prompt = prompt.to_h
    blob = flow.audio_blob(prompt['audio_id'])
    return digest("audio:#{blob.id}:#{blob.checksum}") if blob

    digest("tts:#{@speech.engine}:#{voice(flow)}:#{prompt['text']}") if prompt['text'].present?
  end

  def entries
    @entries ||= Outsider::Voice::IvrFlow.where(account_id: @account.id).with_attached_audios.each_with_object({}) do |flow, result|
      flow.graph_object.prompts.each do |prompt|
        name = name_for(flow, prompt)
        next unless name

        blob = flow.audio_blob(prompt['audio_id'])
        result[name] = blob ? { blob: blob } : { text: prompt['text'], voice: voice(flow) }
      end
    end
  end

  def voice(flow)
    flow.graph_object.start&.dig('data', 'voice') || DEFAULT_VOICE
  end

  def digest(value)
    Digest::SHA256.hexdigest(value)[0, 20]
  end
end
