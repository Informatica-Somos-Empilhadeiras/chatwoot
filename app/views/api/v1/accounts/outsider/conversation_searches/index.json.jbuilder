# Conversa bloqueada: está com outro agente. Vai sem as mensagens, só para mostrar o contato e o agente,
# e com o pedido de transferência que esta pessoa já fez, se houver.
json.payload do
  json.array! @conversations do |conversation|
    json.partial! 'api/v1/conversations/partials/conversation', formats: [:json], conversation: conversation
    if @search.locked?(conversation)
      json.messages []
      json.last_non_activity_message nil
      json.outsider_locked true
      transfer = @transfers[conversation.id]
      json.outsider_transfer_request(transfer && { id: transfer.id, status: transfer.status, created_at: transfer.created_at.to_i })
    end
  end
end
json.contacts @contacts do |contact|
  json.id contact.id
  json.name contact.name
  json.phone_number contact.phone_number
  json.email contact.email
  json.identifier contact.identifier
  json.thumbnail contact.avatar_url
end
