# OUTSIDER: recebe a transcrição feita no navegador (ver app/services/outsider/transcricao.rb).
#   create: anexo de áudio/vídeo de uma mensagem do Chatwoot; quem pode ver a conversa pode transcrever.
#   audio: entrega os bytes do áudio pela mesma origem (o navegador não consegue ler do S3/outro domínio para decodificar).
#   destroy: apaga para transcrever de novo (quem transcreveu ou um administrador).
#   teams: anexo de áudio de uma mensagem da área Teams da própria pessoa.
class Api::V1::Accounts::Outsider::TranscriptionsController < Api::V1::Accounts::BaseController
  rescue_from ::Outsider::Transcricao::Invalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def create
    attachment = find_attachment(params.require(:attachment_id))
    text = ::Outsider::Transcricao.gravar_anexo(attachment, text: params.require(:text), user: Current.user, params: params)
    render json: { attachment_id: attachment.id, transcribed_text: text }
  end

  AUDIO_MAX = 40.megabytes

  def audio
    attachment = find_attachment(params[:attachment_id])
    blob = attachment.file&.blob
    return head(:not_found) unless blob && %w[audio video].include?(attachment.file_type.to_s)
    return head(:payload_too_large) if blob.byte_size > AUDIO_MAX

    response.headers['Cache-Control'] = 'private, max-age=600'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data blob.download, type: blob.content_type.presence || 'application/octet-stream', disposition: 'inline',
                             filename: blob.filename.to_s
  rescue ActiveStorage::FileNotFoundError
    head :not_found
  end

  def destroy
    attachment = find_attachment(params[:attachment_id])
    author = attachment.meta&.dig('outsider_transcricao', 'by')
    return render(json: { error: 'forbidden' }, status: :forbidden) unless Current.account_user.administrator? || author == Current.user.id

    ::Outsider::Transcricao.apagar_anexo(attachment)
    head :no_content
  end

  def teams
    message = ::Outsider::TeamsMessage.joins(thread: :link)
                                      .where(outsider_teams_links: { account_id: Current.account.id, user_id: Current.user.id })
                                      .find(params[:message_id])
    text = ::Outsider::Transcricao.gravar_teams(message, params[:index].to_i, text: params.require(:text), user: Current.user, params: params)
    render json: { message_id: message.id, index: params[:index].to_i, transcribed_text: text }
  end

  private

  def find_attachment(id)
    attachment = Attachment.where(account_id: Current.account.id).find(id)
    authorize attachment.message.conversation, :show?
    attachment
  end
end
