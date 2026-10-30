import settings from './settings/settings.routes';
import conversation from './conversation/conversation.routes';
import { routes as searchRoutes } from '../../modules/search/search.routes';
import { routes as contactRoutes } from './contacts/routes';
import { routes as companyRoutes } from './companies/routes';
import { routes as outsiderWhatsappStatusRoutes } from './outsider/whatsappStatus/routes'; // OUTSIDER: página Status do WhatsApp
import { routes as outsiderCrmRoutes } from './outsider/crm/routes'; // OUTSIDER: CRM de vendas
import { routes as outsiderVoiceRoutes } from './outsider/voice/routes'; // OUTSIDER: Telefonia
import { routes as outsiderPhoneWindowRoutes } from './outsider/voice/windowRoutes'; // OUTSIDER: telefone na janela própria
import { routes as outsiderSettingsRoutes } from './outsider/settings/routes'; // OUTSIDER: Aparência e Automação por bot
import { routes as notificationRoutes } from './notifications/routes';
import { routes as inboxRoutes } from './inbox/routes';
import { frontendURL } from '../../helper/URLHelper';
import helpcenterRoutes from './helpcenter/helpcenter.routes';
import campaignsRoutes from './campaigns/campaigns.routes';
import { routes as captainRoutes } from './captain/captain.routes';
import AppContainer from './Dashboard.vue';
import Suspended from './suspended/Index.vue';
import NoAccounts from './noAccounts/Index.vue';
import OnboardingAccountDetails from './onboarding/Index.vue';
import OnboardingInboxSetup from './onboarding/InboxSetup.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId'),
      component: AppContainer,
      children: [
        ...captainRoutes,
        ...inboxRoutes,
        ...conversation.routes,
        ...settings.routes,
        ...contactRoutes,
        ...companyRoutes,
        ...outsiderWhatsappStatusRoutes, // OUTSIDER
        ...outsiderCrmRoutes, // OUTSIDER
        ...outsiderVoiceRoutes, // OUTSIDER
        ...outsiderSettingsRoutes, // OUTSIDER
        ...searchRoutes,
        ...notificationRoutes,
        ...helpcenterRoutes.routes,
        ...campaignsRoutes.routes,
      ],
    },
    ...outsiderPhoneWindowRoutes, // OUTSIDER
    {
      path: frontendURL('accounts/:accountId/onboarding'),
      name: 'onboarding_account_details',
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
      component: OnboardingAccountDetails,
    },
    {
      path: frontendURL('accounts/:accountId/onboarding/inbox-setup'),
      name: 'onboarding_inbox_setup',
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
      component: OnboardingInboxSetup,
    },
    {
      path: frontendURL('accounts/:accountId/suspended'),
      name: 'account_suspended',
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
      component: Suspended,
    },
    {
      path: frontendURL('no-accounts'),
      name: 'no_accounts',
      component: NoAccounts,
    },
  ],
};
