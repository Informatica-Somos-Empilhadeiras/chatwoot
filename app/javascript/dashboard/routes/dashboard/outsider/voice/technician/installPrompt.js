// OUTSIDER (técnicos): instalar o Chatwoot como app no celular (PWA). O Chrome avisa uma vez, ao carregar a página,
// que dá para instalar (beforeinstallprompt): fica guardado para o botão "Instalar o app" do Perfil. No iPhone não
// existe o botão: a pessoa instala pelo Compartilhar > Adicionar à Tela de Início (só assim o aviso de ligação chega).
import { reactive } from 'vue';

const standalone = () =>
  window.matchMedia?.('(display-mode: standalone)').matches ||
  window.navigator.standalone === true;

export const installState = reactive({
  prompt: null,
  installed: standalone(),
});

window.addEventListener('beforeinstallprompt', event => {
  installState.prompt = event;
});

window.addEventListener('appinstalled', () => {
  installState.installed = true;
  installState.prompt = null;
});

export const installApp = async () => {
  const event = installState.prompt;
  if (!event) return false;
  installState.prompt = null;
  try {
    await event.prompt();
    const choice = await event.userChoice;
    return choice?.outcome === 'accepted';
  } catch {
    return false;
  }
};
