<script setup>
// OUTSIDER: a bolinha de presença do Teams (verde disponível, vermelha ocupado/não incomodar, amarela ausente,
// cinza offline) no canto da foto. Some quando não se sabe a presença (permissões antigas ou pessoa sem Teams).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { presenceOf, presenceStyle } from './presenceStore';

const props = defineProps({
  userId: { type: String, default: null },
  size: { type: Number, default: 12 },
});
const { t } = useI18n();
const style = computed(() => presenceStyle(props.userId));
const label = computed(() => {
  if (!style.value) return '';
  const info = presenceOf(props.userId);
  const base = t(`OUTSIDER_TEAMS_AREA.PRESENCE.${style.value.key}`);
  return info?.activity === 'InAMeeting' || info?.activity === 'InACall'
    ? `${base} · ${t(`OUTSIDER_TEAMS_AREA.PRESENCE.${info.activity === 'InACall' ? 'IN_CALL' : 'IN_MEETING'}`)}`
    : base;
});
const dnd = computed(() => presenceOf(props.userId)?.availability === 'DoNotDisturb');
const away = computed(() => ['Away', 'BeRightBack'].includes(presenceOf(props.userId)?.availability));
const offline = computed(() => ['Offline', 'PresenceUnknown'].includes(presenceOf(props.userId)?.availability));
</script>

<template>
  <span
    v-if="style"
    class="grid rounded-full place-items-center bg-n-surface-1"
    :style="{ width: `${size + 4}px`, height: `${size + 4}px` }"
    :title="label"
    data-teams-presence
    :data-availability="presenceOf(userId)?.availability"
  >
    <span
      class="grid rounded-full place-items-center"
      :style="{ width: `${size}px`, height: `${size}px`, background: style.color }"
    >
      <!-- traço do "não incomodar", círculo vazio do ausente/offline, como no Teams -->
      <span
        v-if="dnd"
        class="block bg-white rounded-full"
        :style="{ width: `${size * 0.55}px`, height: `${Math.max(2, size * 0.16)}px` }"
      />
      <span
        v-else-if="offline"
        class="block rounded-full bg-n-surface-1"
        :style="{ width: `${size * 0.5}px`, height: `${size * 0.5}px` }"
      />
      <span
        v-else-if="away"
        class="block border-2 border-white rounded-full"
        :style="{ width: `${size * 0.5}px`, height: `${size * 0.5}px`, borderRightColor: 'transparent' }"
      />
    </span>
  </span>
</template>
