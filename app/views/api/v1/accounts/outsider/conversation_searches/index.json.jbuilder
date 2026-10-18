# Conversa bloqueada: está com outro agente. Vai sem as mensagens, só para mostrar o contato e o agente.
json.payload do
  json.array! @conversations do |conversation|
    json.partial! 'api/v1/conversations/partials/conversation', formats: [:json], conversation: conversation
    if @search.locked?(conversation)
      json.messages []
      json.last_non_activity_message nil
      json.outsider_locked true
    end
  end
end
