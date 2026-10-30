// OUTSIDER: aparência da conta (Configurações > Aparência) aplicada para todos da conta:
//  - título da aba do navegador
//  - favicon (com a bolinha de não lidas desenhada por cima, ver outsiderFaviconHref)
//  - logo do canto do menu (Logo.vue lê brandingState.logoUrl)
//  - papel de parede das conversas (CSS que vence o fundo padrão do MessagesView.vue)
// Recarrega quando o administrador salva (aviso 'branding' pelo canal da conta).
import { reactive, watch, onMounted, onBeforeUnmount } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import BrandingAPI from 'dashboard/api/outsider/branding';

const STYLE_ID = 'outsider-branding-style';
const NOTICE_EVENT = 'outsider:notice';

export const brandingState = reactive({
  loaded: false,
  title: null,
  faviconUrl: null,
  logoUrl: null,
  wallpaperUrl: null,
  wallpaperFit: 'cover',
  wallpaperDim: 60,
});

let originalTitle = null;
let badgeCache = { url: null, data: null };

const fromResponse = data => ({
  title: data.title || null,
  faviconUrl: data.favicon_url || null,
  logoUrl: data.logo_url || null,
  wallpaperUrl: data.wallpaper_url || null,
  wallpaperFit: data.wallpaper_fit || 'cover',
  wallpaperDim: Number.isFinite(data.wallpaper_dim) ? data.wallpaper_dim : 60,
});

// favicon com a bolinha vermelha de "mensagem nova", desenhado uma vez por imagem
const buildBadge = url => {
  if (badgeCache.url === url) return;
  badgeCache = { url, data: null };
  const image = new Image();
  image.onload = () => {
    try {
      const size = 64;
      const canvas = document.createElement('canvas');
      canvas.width = size;
      canvas.height = size;
      const context = canvas.getContext('2d');
      context.drawImage(image, 0, 0, size, size);
      context.beginPath();
      context.arc(size - 14, 14, 13, 0, 2 * Math.PI);
      context.fillStyle = '#e5484d';
      context.fill();
      context.lineWidth = 4;
      context.strokeStyle = '#ffffff';
      context.stroke();
      if (badgeCache.url === url)
        badgeCache.data = canvas.toDataURL('image/png');
    } catch {
      // imagem que o navegador não deixa desenhar: fica sem bolinha
    }
  };
  image.src = url;
};

// usado pelo helper/AudioAlerts/faviconHelper.js; null = favicon padrão do Chatwoot
export const outsiderFaviconHref = (withBadge = false) => {
  const url = brandingState.faviconUrl;
  if (!url) return null;
  return (withBadge && badgeCache.url === url && badgeCache.data) || url;
};

const applyFavicon = () => {
  document.querySelectorAll('.favicon').forEach(link => {
    link.href = outsiderFaviconHref() || `/favicon-${link.sizes[[0]]}.png`;
  });
  if (brandingState.faviconUrl) buildBadge(brandingState.faviconUrl);
};

const applyTitle = () => {
  if (originalTitle === null) originalTitle = document.title;
  document.title = brandingState.title || originalTitle;
};

const cssUrl = url => `url("${String(url).replace(/["\\\n]/g, '')}")`;

const applyWallpaper = () => {
  const root = document.documentElement;
  let style = document.getElementById(STYLE_ID);
  if (!brandingState.wallpaperUrl) {
    root.removeAttribute('data-outsider-wallpaper');
    style?.remove();
    return;
  }
  if (!style) {
    style = document.createElement('style');
    style.id = STYLE_ID;
    document.head.appendChild(style);
  }
  const dim = Math.min(Math.max(brandingState.wallpaperDim, 0), 90) / 100;
  const tile = brandingState.wallpaperFit === 'tile';
  const layout = tile
    ? 'background-repeat: repeat !important; background-size: auto, 420px auto !important; background-position: top left !important;'
    : 'background-repeat: no-repeat !important; background-size: cover !important; background-position: center center !important;';
  const image = cssUrl(brandingState.wallpaperUrl);
  style.textContent = `
html[data-outsider-wallpaper] .conversation-panel {
  background-image: linear-gradient(rgba(255,255,255,${dim}), rgba(255,255,255,${dim})), ${image} !important;
  ${layout}
}
html.dark[data-outsider-wallpaper] .conversation-panel,
html[data-outsider-wallpaper] .dark .conversation-panel {
  background-image: linear-gradient(rgba(0,0,0,${dim}), rgba(0,0,0,${dim})), ${image} !important;
}`;
  root.setAttribute('data-outsider-wallpaper', '');
};

export const applyBranding = () => {
  applyTitle();
  applyFavicon();
  applyWallpaper();
};

export const setBranding = data => {
  Object.assign(brandingState, fromResponse(data), { loaded: true });
  applyBranding();
};

export const loadBranding = async () => {
  try {
    const { data } = await BrandingAPI.get();
    setBranding(data);
  } catch {
    // sem a aparência da conta, fica a padrão
  }
};

export const useAccountBranding = () => {
  const accountId = useMapGetter('getCurrentAccountId');
  const onNotice = data => {
    if (data?.kind === 'branding') loadBranding();
  };

  watch(accountId, id => {
    if (id) loadBranding();
  });

  onMounted(() => {
    if (accountId.value) loadBranding();
    emitter.on(NOTICE_EVENT, onNotice);
  });

  onBeforeUnmount(() => emitter.off(NOTICE_EVENT, onNotice));
};
