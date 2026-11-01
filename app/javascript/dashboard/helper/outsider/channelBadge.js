// OUTSIDER: de onde veio a conversa, para o selo no canto da foto (lista, cabeçalho e busca).
// A caixa da Evolution é uma caixa "API" do Chatwoot: ela é reconhecida pelo endereço do webhook
// (ver whatsappMessage.js) e ganha o selo do WhatsApp. E-mail do Outlook/Microsoft e do Gmail têm
// cor própria; os outros e-mails ficam com o envelope.
import { isEvolutionInbox } from './whatsappMessage';

const CHANNELS = {
  whatsapp: { icon: 'i-ri-whatsapp-fill', color: '#25D366', label: 'WhatsApp' },
  outlook: { icon: 'i-ri-mail-fill', color: '#0078D4', label: 'Outlook' },
  gmail: { icon: 'i-ri-mail-fill', color: '#EA4335', label: 'Gmail' },
  email: { icon: 'i-ri-mail-fill', color: '#64748B', label: 'E-mail' },
  instagram: {
    icon: 'i-ri-instagram-line',
    color: 'linear-gradient(45deg, #F9CE34 0%, #EE2A7B 50%, #6228D7 100%)',
    label: 'Instagram',
  },
  messenger: {
    icon: 'i-ri-messenger-fill',
    color: '#0866FF',
    label: 'Messenger',
  },
  telegram: { icon: 'i-ri-telegram-fill', color: '#229ED9', label: 'Telegram' },
  tiktok: { icon: 'i-ri-tiktok-fill', color: '#111111', label: 'TikTok' },
  line: { icon: 'i-ri-line-fill', color: '#06C755', label: 'LINE' },
  twitter: { icon: 'i-ri-twitter-x-fill', color: '#111111', label: 'X' },
  sms: { icon: 'i-ri-message-2-fill', color: '#7C3AED', label: 'SMS' },
  web: { icon: 'i-ri-global-line', color: '#2563EB', label: 'Site' },
  voice: { icon: 'i-ri-phone-fill', color: '#0D9488', label: 'Telefone' },
  api: { icon: 'i-ri-plug-fill', color: '#64748B', label: 'API' },
};

const emailKind = inbox => {
  const provider = String(inbox.provider || '').toLowerCase();
  const address = String(inbox.email || '').toLowerCase();
  if (provider === 'microsoft' || /@(outlook|hotmail|live)\./.test(address))
    return 'outlook';
  if (provider === 'google' || /@(gmail|googlemail)\./.test(address))
    return 'gmail';
  return 'email';
};

export const channelKind = inbox => {
  if (!inbox?.channel_type) return null;
  switch (inbox.channel_type) {
    case 'Channel::Whatsapp':
      return 'whatsapp';
    case 'Channel::Api':
      return isEvolutionInbox(inbox) ? 'whatsapp' : 'api';
    case 'Channel::Email':
      return emailKind(inbox);
    case 'Channel::Instagram':
      return 'instagram';
    case 'Channel::FacebookPage':
      return 'messenger';
    case 'Channel::Telegram':
      return 'telegram';
    case 'Channel::Tiktok':
      return 'tiktok';
    case 'Channel::Line':
      return 'line';
    case 'Channel::TwitterProfile':
      return 'twitter';
    case 'Channel::WebWidget':
      return 'web';
    case 'Channel::Voice':
      return 'voice';
    case 'Channel::TwilioSms':
      return inbox.medium === 'whatsapp' ? 'whatsapp' : 'sms';
    case 'Channel::Sms':
      return 'sms';
    default:
      return 'api';
  }
};

export const channelBadge = inbox => {
  const kind = channelKind(inbox);
  return kind ? { kind, ...CHANNELS[kind] } : null;
};
