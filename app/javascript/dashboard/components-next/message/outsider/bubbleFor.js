// OUTSIDER: bolhas estilo WhatsApp. O Message.vue pergunta aqui antes das bolhas originais; quando
// a mensagem não é de nenhum destes tipos, segue o caminho normal do Chatwoot.
import MediaAlbumBubble from './MediaAlbum.vue';
import ContactCardBubble from './ContactCard.vue';
import LocationCardBubble from './LocationCard.vue';
import VoiceBubble from './VoiceBubble.vue';
import NoticeBubble from './NoticeBubble.vue';
import { isMediaAlbum } from 'dashboard/helper/outsider/mediaAlbum';
import { isContactCardMessage } from 'dashboard/helper/outsider/contactCard';
import { isLocationMessage } from 'dashboard/helper/outsider/location';
import { isVoiceWithHeader } from 'dashboard/helper/outsider/voiceNote';
import { evolutionNoticeOf } from 'dashboard/helper/outsider/evolutionNotice';

// mesmo caso em que o Chatwoot usaria a bolha de áudio, mais o áudio de grupo (só com quem enviou)
const isVoiceMessage = props =>
  !props.isEmailInbox &&
  Array.isArray(props.attachments) &&
  props.attachments.length === 1 &&
  props.attachments[0].fileType === 'audio' &&
  (!props.content || isVoiceWithHeader(props));

export const outsiderBubbleFor = props => {
  if (evolutionNoticeOf(props)) return NoticeBubble;
  if (isMediaAlbum(props)) return MediaAlbumBubble;
  if (isContactCardMessage(props)) return ContactCardBubble;
  if (isLocationMessage(props)) return LocationCardBubble;
  if (isVoiceMessage(props)) return VoiceBubble;
  return null;
};
