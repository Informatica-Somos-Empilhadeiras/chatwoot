# OUTSIDER: a cópia que a Evolution grava do que o bot mandou entra como mensagem do bot (ver
# app/services/outsider/bot/echo.rb). Arquivo à parte do outsider_bot.rb para a correção valer sozinha.
Rails.application.config.to_prepare do
  Messages::MessageBuilder.prepend(Outsider::Bot::EchoBuilder) unless Messages::MessageBuilder < Outsider::Bot::EchoBuilder
end
