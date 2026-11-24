// OUTSIDER: telas dos Aplicativos. provider = empresa (microsoft ou google). Cada tela é a mesma para as duas empresas:
// e-mail (Outlook/Gmail), arquivos (OneDrive/Drive) e agenda.
//   /apps/microsoft/outlook?folder=...&message=...   /apps/google/gmail?folder=...&message=...
//   /apps/microsoft/onedrive                          /apps/google/drive
//   /apps/microsoft/agenda?view=day|week|month&date=AAAA-MM-DD   /apps/google/agenda
import { frontendURL } from 'dashboard/helper/URLHelper';
import MailArea from './mail/MailArea.vue';
import DriveArea from './drive/DriveArea.vue';
import CalendarArea from './calendar/CalendarArea.vue';
import { MAIL_ROUTE, DRIVE_ROUTE, CALENDAR_ROUTE } from './appsStore';

const meta = { permissions: ['administrator', 'agent'] };

export const routes = [
  {
    path: frontendURL(
      'accounts/:accountId/apps/:provider(microsoft|google)/:mailApp(outlook|gmail)'
    ),
    name: MAIL_ROUTE,
    component: MailArea,
    meta,
  },
  {
    path: frontendURL(
      'accounts/:accountId/apps/:provider(microsoft|google)/:driveApp(onedrive|drive)'
    ),
    name: DRIVE_ROUTE,
    component: DriveArea,
    meta,
  },
  {
    path: frontendURL(
      'accounts/:accountId/apps/:provider(microsoft|google)/agenda'
    ),
    name: CALENDAR_ROUTE,
    component: CalendarArea,
    meta,
  },
];
