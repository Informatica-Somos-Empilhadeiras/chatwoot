# OUTSIDER: manda uma foto de produto (Outsider::Erp::ProductPhotos) para o cliente pelo WhatsApp, numa conversa que já
# existe: a do chat de onde o orçamento foi aberto ou, sem ela, a conversa aberta do contato numa caixa de WhatsApp que a
# pessoa atende (Outsider::Erp::Delivery, que acha a conversa em todos os cadastros do cliente). Nunca abre conversa nova.
# BMP vai convertida em JPG.
class Outsider::Erp::PhotoSender
  include Outsider::Erp::Delivery

  def initialize(account_user)
    @account_user = account_user
    @account = account_user.account
    @user = account_user.user
  end

  # photo: o que devolve { 'filename', 'content', 'content_type' }; conversation: a do chat (opcional); contact_id: sem ela
  def deliver(photo, conversation:, contact_id:, message: nil)
    target = conversation || open_conversation(contact_id) || raise(Blocked, 'no_conversation')
    text = clean(message, MAX_MESSAGE)
    file = whatsapp_image(photo.call)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(file['content']), filename: file['filename'],
                                                  content_type: file['content_type'])
    post(target, text, attachments: [blob.signed_id])
    target
  end

  private

  def open_conversation(contact_id)
    contact = @account.contacts.find_by(id: contact_id)
    return unless contact

    recipients.whatsapp_inboxes.filter_map { |inbox| existing_conversation(inbox, contact) }.max_by(&:last_activity_at)
  end

  # o WhatsApp não mostra BMP como foto (muitas fotos do ERP são BMP): vai convertida em JPG, com o mesmo nome
  def whatsapp_image(file)
    return file unless file['content_type'] == 'image/bmp'

    Tempfile.create(['foto', '.bmp'], binmode: true) do |source|
      source.write(file['content'])
      source.flush
      jpg = ImageProcessing::MiniMagick.source(source.path).convert('jpg').saver(quality: 85).call
      { 'filename' => "#{File.basename(file['filename'], '.*')}.jpg", 'content' => File.binread(jpg.path), 'content_type' => 'image/jpeg' }
    ensure
      jpg&.close!
    end
  end

  def recipients
    @recipients ||= Outsider::Erp::BudgetRecipients.new(@account_user)
  end
end
