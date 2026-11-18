<script setup>
// OUTSIDER (técnicos): topo das abas do Meu telefone: a pessoa (ou o título da aba) e a bolinha de situação
// (Disponível, Ocupado, Conectando, Sem conexão...), que junta a situação do Chatwoot com a linha do telefone.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { phone } from '../phone';

defineProps({
  title: { type: String, default: '' },
});

const { t } = useI18n();
const user = useMapGetter('getCurrentUser');
const availability = useMapGetter('getCurrentUserAvailability');

const KIND = { technician: 'TECHNICIAN', administrator: 'ADMIN' };

const role = computed(() =>
  [
    t(`OUTSIDER_VOICE.TECH.KIND.${KIND[phone.kind] || 'AGENT'}`),
    phone.extension &&
      t('OUTSIDER_VOICE.TECH.EXTENSION', { extension: phone.extension }),
    phone.branch,
  ]
    .filter(Boolean)
    .join(' · ')
);

// a linha manda: sem central não adianta dizer "Disponível". Dormindo (app escondido) conta como disponível.
const status = computed(() => {
  if (phone.sleeping) return 'online';
  if (phone.status === 'connecting') return 'connecting';
  if (['offline', 'failed'].includes(phone.status)) return 'disconnected';
  if (phone.status === 'other_tab') return 'other_tab';
  if (availability.value === 'busy') return 'busy';
  if (availability.value === 'offline') return 'offline';
  return 'online';
});
</script>

<template>
  <header class="flex items-center gap-3 px-4 pt-3 pb-3 border-b border-n-weak">
    <template v-if="!title">
      <Avatar
        :name="user?.name || ''"
        :src="user?.avatar_url || ''"
        :size="40"
        rounded-full
      />
      <div class="flex-1 min-w-0">
        <p class="text-base font-semibold truncate text-n-slate-12">
          {{ user?.name }}
        </p>
        <p class="text-xs truncate text-n-slate-11">{{ role }}</p>
      </div>
    </template>
    <h1 v-else class="flex-1 text-2xl font-semibold text-n-slate-12">
      {{ title }}
    </h1>
    <span
      class="outsider-tech-pill"
      :class="`is-${status}`"
      data-testid="outsider-tech-status"
    >
      <span class="outsider-tech-pill__dot" />
      {{ t(`OUTSIDER_VOICE.TECH.STATUS.${status.toUpperCase()}`) }}
    </span>
  </header>
</template>

<style scoped>
.outsider-tech-pill {
  display: inline-flex;
  align-items: center;
  gap: 0.375rem;
  padding: 0.35rem 0.65rem;
  border-radius: 999px;
  font-size: 0.75rem;
  font-weight: 600;
  white-space: nowrap;
  background: #dcfce7;
  color: #166534;
}

.outsider-tech-pill__dot {
  width: 0.5rem;
  height: 0.5rem;
  border-radius: 50%;
  background: #22c55e;
}

.outsider-tech-pill.is-busy {
  background: #fef3c7;
  color: #92400e;
}

.outsider-tech-pill.is-busy .outsider-tech-pill__dot {
  background: #f59e0b;
}

.outsider-tech-pill.is-connecting,
.outsider-tech-pill.is-other_tab,
.outsider-tech-pill.is-offline {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-11));
}

.outsider-tech-pill.is-connecting .outsider-tech-pill__dot,
.outsider-tech-pill.is-other_tab .outsider-tech-pill__dot,
.outsider-tech-pill.is-offline .outsider-tech-pill__dot {
  background: rgb(var(--slate-9));
}

.outsider-tech-pill.is-disconnected {
  background: #fee2e2;
  color: #b91c1c;
}

.outsider-tech-pill.is-disconnected .outsider-tech-pill__dot {
  background: #ef4444;
}
</style>
