<script setup>
// OUTSIDER (técnicos): lembrete no Teclado enquanto este aparelho não recebe o aviso de ligação. Sem o aviso a ligação
// só toca com o app aberto; com um toque ativa (ou leva ao Perfil quando o iPhone precisa instalar o app antes).
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useTechPush } from './useTechPush';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { pushStatus, working, enablePush } = useTechPush();

const shown = computed(() =>
  ['OFF', 'BLOCKED', 'INSTALL_FIRST'].includes(pushStatus.value)
);

const openProfile = () =>
  router.replace({
    name: 'outsider_my_phone',
    params: { ...route.params, tab: 'perfil' },
  });
</script>

<template>
  <div
    v-if="shown"
    class="flex items-center gap-3 px-3 py-2.5 mx-4 mt-3 rounded-xl bg-n-amber-3 text-n-amber-12"
    data-testid="outsider-tech-push-nudge"
  >
    <span class="i-lucide-bell-off size-5 shrink-0" />
    <span class="flex-1 text-xs leading-4">
      {{ t(`OUTSIDER_VOICE.TECH.NUDGE.${pushStatus}`) }}
    </span>
    <button
      v-if="pushStatus === 'OFF'"
      type="button"
      class="px-3 py-1.5 text-xs font-bold rounded-full shrink-0 bg-n-amber-12 text-n-amber-1"
      :disabled="working"
      @click="enablePush"
    >
      {{ t('OUTSIDER_VOICE.TECH.NUDGE.ENABLE') }}
    </button>
    <button
      v-else
      type="button"
      class="px-3 py-1.5 text-xs font-bold rounded-full shrink-0 bg-n-amber-12 text-n-amber-1"
      @click="openProfile"
    >
      {{ t('OUTSIDER_VOICE.TECH.NUDGE.HOW') }}
    </button>
  </div>
</template>
