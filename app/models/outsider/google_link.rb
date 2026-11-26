# OUTSIDER: a conta Google de um colaborador no bloco Google dos Aplicativos (Gmail, Agenda e Drive, em nome dele).
# Tokens cifrados; scopes = as permissões que ele aceitou na tela do Google (ele pode desmarcar alguma: a tela daquela
# parte pede para entrar de novo). status 'reconnect' quando o Google não aceita mais o acesso (senha trocada, acesso
# retirado) e 'disconnected' quando a pessoa desconecta. history_id: até onde o observador já olhou o Gmail.
class Outsider::GoogleLink < ApplicationRecord
  self.table_name = 'outsider_google_links'

  STATUSES = %w[active reconnect disconnected].freeze
  SCOPE = 'https://www.googleapis.com/auth/'.freeze
  # cada parte e a permissão que ela precisa. calendars: a lista das agendas da pessoa (inclusive as compartilhadas com
  # ela); quem entrou antes dela continua só com a agenda principal até "Entrar de novo".
  FEATURES = { mail: "#{SCOPE}gmail.modify", calendar: "#{SCOPE}calendar.events", drive: "#{SCOPE}drive",
               calendars: "#{SCOPE}calendar.calendarlist.readonly" }.freeze

  belongs_to :account
  belongs_to :user

  validates :google_user_id, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :account_id }
  validates :google_user_id, uniqueness: { scope: :account_id }

  scope :active, -> { where(status: 'active') }

  def app
    Outsider::GoogleApp.find_by(account_id: account_id)
  end

  def allows?(feature)
    status == 'active' && scope_list.include?(FEATURES.fetch(feature))
  end

  def scope_list
    scopes.to_s.split
  end

  def access_token
    Outsider::Teams::Secret.decrypt('google_access_token', access_token_encrypted)
  end

  def access_token=(value)
    self.access_token_encrypted = Outsider::Teams::Secret.encrypt('google_access_token', value)
  end

  def refresh_token
    Outsider::Teams::Secret.decrypt('google_refresh_token', refresh_token_encrypted)
  end

  def refresh_token=(value)
    self.refresh_token_encrypted = Outsider::Teams::Secret.encrypt('google_refresh_token', value) if value.present?
  end
end
