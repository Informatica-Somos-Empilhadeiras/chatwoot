// OUTSIDER: o Teams agora fica dentro do bloco Microsoft dos Aplicativos (apps/sidebar.js), ao lado do Outlook, do
// OneDrive e da Agenda; Chats e Canais são as abas da própria tela do Teams. O Sidebar.vue continua chamando
// teamsSidebarItems, que devolve os blocos dos aplicativos.
import { appsSidebarItems } from '../apps/sidebar';

export const teamsSidebarItems = (t, accountScopedRoute) =>
  appsSidebarItems(t, accountScopedRoute);
