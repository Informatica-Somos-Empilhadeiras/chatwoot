// OUTSIDER: favicon da conta (Configurações > Aparência), quando houver
import { outsiderFaviconHref } from 'dashboard/routes/dashboard/outsider/branding/useAccountBranding';

export const showBadgeOnFavicon = () => {
  const favicons = document.querySelectorAll('.favicon');

  favicons.forEach(favicon => {
    const newFileName = `/favicon-badge-${favicon.sizes[[0]]}.png`;
    favicon.href = outsiderFaviconHref(true) || newFileName; // OUTSIDER
  });
};

export const initFaviconSwitcher = () => {
  const favicons = document.querySelectorAll('.favicon');

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      favicons.forEach(favicon => {
        const oldFileName = `/favicon-${favicon.sizes[[0]]}.png`;
        favicon.href = outsiderFaviconHref() || oldFileName; // OUTSIDER
      });
    }
  });
};
