<script setup>
// OUTSIDER (técnicos): aba Recentes do Meu telefone: as ligações dos últimos 30 dias, por dia. Perdidas em vermelho
// com "Ligar de volta" (quem perde também recebe o push "Ligação perdida"); as outras ligam de novo com um toque.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { dial } from '../phone';
import { formatPhone, formatTalkTime } from '../format';
import TechHeader from './TechHeader.vue';
import { colleagueOf, techState } from './techStore';

const { t, locale } = useI18n();
const onlyMissed = ref(false);

const missedCount = computed(
  () => techState.recent.filter(call => call.missed).length
);
const list = computed(() =>
  onlyMissed.value
    ? techState.recent.filter(call => call.missed)
    : techState.recent
);

const dayKey = date =>
  `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;

const dayLabel = date => {
  const today = new Date();
  const yesterday = new Date();
  yesterday.setDate(today.getDate() - 1);
  if (dayKey(date) === dayKey(today)) return t('OUTSIDER_VOICE.TECH.TODAY');
  if (dayKey(date) === dayKey(yesterday))
    return t('OUTSIDER_VOICE.TECH.YESTERDAY');
  return date.toLocaleDateString(locale.value.replace('_', '-'), {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
};

const groups = computed(() => {
  const result = [];
  list.value.forEach(call => {
    const date = new Date(call.started_at);
    const key = dayKey(date);
    let group = result[result.length - 1];
    if (!group || group.key !== key) {
      group = { key, label: dayLabel(date), calls: [] };
      result.push(group);
    }
    group.calls.push(call);
  });
  return result;
});

const nameOf = call => {
  if (call.name) return call.name;
  if (call.internal) {
    return (
      colleagueOf(call.number)?.name ||
      t('OUTSIDER_VOICE.CALL.INTERNAL', { extension: call.number })
    );
  }
  return formatPhone(call.number);
};

// número sem nome: o símbolo do telefone no lugar de "(1" como iniciais
const iconOf = call =>
  !call.thumbnail && !/\p{L}/u.test(nameOf(call)) ? 'i-lucide-phone' : null;

const time = call =>
  new Date(call.started_at).toLocaleTimeString(locale.value.replace('_', '-'), {
    hour: '2-digit',
    minute: '2-digit',
  });

const kindOf = call => {
  if (call.missed) return 'MISSED';
  if (call.direction === 'in')
    return call.status === 'busy' ? 'DECLINED' : 'RECEIVED';
  return call.status === 'answered' ? 'MADE' : 'NOT_ANSWERED';
};

const detail = call => {
  const parts = [
    t(`OUTSIDER_VOICE.TECH.CALL_KIND.${kindOf(call)}`),
    time(call),
  ];
  if (call.talk_seconds)
    parts.push(
      call.talk_seconds < 60
        ? `${call.talk_seconds} s`
        : formatTalkTime(call.talk_seconds)
    );
  else if (call.internal)
    parts.push(t('OUTSIDER_VOICE.TECH.EXTENSION', { extension: call.number }));
  return parts.join(' · ');
};

const callBack = call => {
  const error = dial(call.number);
  if (error) useAlert(t(`OUTSIDER_VOICE.PHONE.ERRORS.${error}`));
};
</script>

<template>
  <div>
    <TechHeader :title="t('OUTSIDER_VOICE.TECH.TABS.RECENT')" />
    <div class="flex gap-2 px-4 pt-3">
      <button
        type="button"
        class="outsider-tech-chip"
        :class="{ 'is-on': !onlyMissed }"
        @click="onlyMissed = false"
      >
        {{ t('OUTSIDER_VOICE.TECH.ALL_CALLS') }}
      </button>
      <button
        type="button"
        class="outsider-tech-chip"
        :class="{ 'is-on': onlyMissed }"
        data-testid="outsider-tech-only-missed"
        @click="onlyMissed = true"
      >
        {{ t('OUTSIDER_VOICE.TECH.MISSED_CALLS', { count: missedCount }) }}
      </button>
    </div>

    <p
      v-if="!list.length"
      class="px-6 py-10 text-sm text-center text-n-slate-11"
    >
      {{
        techState.recentLoaded
          ? t('OUTSIDER_VOICE.TECH.RECENT_EMPTY')
          : t('OUTSIDER_VOICE.TECH.LOADING')
      }}
    </p>

    <section v-for="group in groups" :key="group.key">
      <h2
        class="px-4 pt-4 pb-1 text-xs font-bold tracking-wide uppercase text-n-slate-11"
      >
        {{ group.label }}
      </h2>
      <div
        v-for="call in group.calls"
        :key="call.id"
        class="flex items-center gap-3 px-4 py-2.5"
        :data-testid="`outsider-tech-recent-${call.id}`"
      >
        <Avatar
          :name="nameOf(call)"
          :src="call.thumbnail || ''"
          :icon-name="iconOf(call)"
          :size="42"
          rounded-full
          class="shrink-0"
        />
        <span class="flex-1 min-w-0">
          <span
            class="block font-semibold truncate"
            :class="call.missed ? 'text-n-ruby-11' : 'text-n-slate-12'"
          >
            {{ nameOf(call) }}
          </span>
          <span
            class="flex items-center gap-1 text-xs truncate text-n-slate-11"
          >
            <span
              class="size-3 shrink-0"
              :class="[
                call.direction === 'in'
                  ? 'i-lucide-arrow-down-left'
                  : 'i-lucide-arrow-up-right',
                call.missed
                  ? 'text-n-ruby-11'
                  : call.direction === 'in'
                    ? 'text-n-teal-11'
                    : 'text-n-blue-11',
              ]"
            />
            {{ detail(call) }}
          </span>
        </span>
        <button
          v-if="call.missed"
          type="button"
          class="outsider-tech-callback"
          @click="callBack(call)"
        >
          {{ t('OUTSIDER_VOICE.TECH.CALL_BACK') }}
        </button>
        <button
          v-else
          type="button"
          class="outsider-tech-round"
          :aria-label="t('OUTSIDER_VOICE.TECH.CALL_TO', { name: nameOf(call) })"
          @click="callBack(call)"
        >
          <span class="i-lucide-phone size-5" />
        </button>
      </div>
    </section>
    <div class="h-4" />
  </div>
</template>

<style scoped>
.outsider-tech-chip {
  flex: none;
  padding: 0.35rem 0.8rem;
  border-radius: 999px;
  font-size: 0.8rem;
  font-weight: 500;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}

.outsider-tech-chip.is-on {
  background: var(--outsider-brand, #00663b);
  color: #fff;
}

.outsider-tech-round {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 2.5rem;
  height: 2.5rem;
  flex: none;
  border-radius: 50%;
  background: #e8f7ee;
  color: #137333;
}

.outsider-tech-callback {
  flex: none;
  padding: 0.45rem 0.7rem;
  border-radius: 999px;
  font-size: 0.78rem;
  font-weight: 700;
  background: #e8f7ee;
  color: #137333;
}
</style>
