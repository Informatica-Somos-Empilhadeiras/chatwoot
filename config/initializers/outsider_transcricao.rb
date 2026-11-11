# OUTSIDER: transcrição de áudios feita no navegador do agente (Whisper em WebAssembly/WebGPU) e guardada uma vez:
# no WhatsApp vai para attachments.meta['transcribed_text'] (o mesmo lugar que o Chatwoot usa quando transcreve pelo
# Captain, então a bolha, a busca e a prévia da lista já mostram); no Teams fica no anexo da mensagem.
# Ver app/controllers/api/v1/accounts/outsider/transcriptions_controller.rb e app/services/outsider/transcricao.rb
Rails.application.routes.prepend do
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resources :accounts, only: [] do
        scope module: :accounts do
          namespace :outsider do
            post 'transcriptions', to: 'transcriptions#create'
            # o arquivo de áudio pelo Chatwoot (mesma origem), para o navegador decodificar sem bloqueio de CORS
            get 'transcriptions/:attachment_id/audio', to: 'transcriptions#audio'
            delete 'transcriptions/:attachment_id', to: 'transcriptions#destroy'
            post 'transcriptions/teams/:message_id', to: 'transcriptions#teams'
          end
        end
      end
    end
  end
end
