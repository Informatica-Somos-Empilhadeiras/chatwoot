// OUTSIDER: o que a caixa de resposta (ReplyBox.vue) ganhou, fora do arquivo original:
// - o áudio gravado no VoiceRecorder.vue vai sozinho, como mensagem de voz; o texto digitado fica na caixa;
// - a caixa de texto começa com uma linha e cresce com o texto (replyBoxOutsider.css).
// A barra de botões é o ComposerBar.vue, que o ReplyBox importa no lugar da ReplyBottomPanel.
import './replyBoxOutsider.css';

export default {
  methods: {
    outsiderSendVoice(voice) {
      this.sendMessage(
        this.setReplyToInPayload({
          conversationId: this.currentChat.id,
          message: '',
          private: false,
          sender: this.sender,
          ...voice,
        })
      );
      this.resetReplyToMessage();
      this.resetAudioRecorderInput();
    },
  },
};
