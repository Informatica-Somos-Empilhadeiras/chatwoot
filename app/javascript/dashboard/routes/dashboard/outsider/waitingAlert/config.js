// OUTSIDER: tempos do aviso de clientes esperando (ver WaitingConversationsAlert.vue).
// O aviso aparece quando uma conversa está aberta, sem agente, há mais de ALERT_AFTER
// segundos. Se o agente fechar o aviso, ele volta depois de REMIND_EVERY segundos
// enquanto ainda houver alguém esperando.
export const ALERT_AFTER = 60;
export const REMIND_EVERY = 120;
export const POLL_EVERY = 20;
// a partir daqui o tempo de espera fica vermelho
export const LATE_AFTER = 5 * 60;
export const MAX_LISTED = 5;
export const SOUND_URL = '/audio/dashboard/bell.mp3';
export const SHOW_WAITING_TAB_EVENT = 'outsider_show_waiting_tab';
