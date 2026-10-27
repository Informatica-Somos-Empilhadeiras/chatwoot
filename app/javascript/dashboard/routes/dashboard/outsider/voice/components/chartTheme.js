// OUTSIDER: cores dos gráficos da Telefonia (Entrega 24), tiradas do tema do Chatwoot e relidas quando ele
// muda (claro/escuro). Cada tipo de ligação tem sempre a mesma cor, em todos os gráficos.
import { ref, computed } from 'vue';
import { useMutationObserver } from '@vueuse/core';

export const SERIES = {
  inbound_answered: { token: '--teal-9', dot: 'bg-n-teal-9' },
  missed: { token: '--ruby-9', dot: 'bg-n-ruby-9' },
  outbound: { token: '--blue-9', dot: 'bg-n-blue-9' },
  internal: { token: '--slate-8', dot: 'bg-n-slate-8' },
  minutes: { token: '--blue-9', dot: 'bg-n-blue-9' },
  talk: { token: '--teal-9', dot: 'bg-n-teal-9' },
  wait: { token: '--amber-9', dot: 'bg-n-amber-9' },
};

const token = name =>
  `rgb(${getComputedStyle(document.documentElement).getPropertyValue(name).trim()})`;

export const useChartTheme = () => {
  const version = ref(0);
  useMutationObserver(
    document.documentElement,
    () => {
      version.value += 1;
    },
    { attributes: true, attributeFilter: ['class'] }
  );
  return computed(() => {
    // eslint-disable-next-line no-unused-expressions
    version.value;
    return {
      color: key => token(SERIES[key].token),
      text: token('--slate-11'),
      grid: token('--slate-5'),
      surface: token('--solid-2'),
    };
  });
};
