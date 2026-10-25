<script setup>
// OUTSIDER: colegas com ramal no telefone (Entrega 23), com o ponto verde de quem está com o telefone
// conectado. Clicar liga para o ramal (ou transfere a ligação para ele). Atualiza a cada 30 s.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useIntervalFn } from '@vueuse/core';
import VoiceAPI from 'dashboard/api/outsider/voice';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { phone } from './phone';

const props = defineProps({
  icon: { type: String, default: 'i-lucide-phone' },
  // ramal que não aparece (quem está do outro lado da ligação, ao transferir)
  exclude: { type: String, default: '' },
});

const emit = defineEmits(['pick']);

const { t } = useI18n();
const team = ref([]);

const colleagues = computed(() =>
  team.value.filter(
    person => ![phone.extension, props.exclude].includes(person.extension)
  )
);

const load = async () => {
  try {
    const { data } = await VoiceAPI.team();
    team.value = data;
  } catch {
    // sem a lista, ainda dá para digitar o ramal
  }
};

useIntervalFn(load, 30000);
onMounted(load);
</script>

<template>
  <div class="flex flex-col">
    <p v-if="!colleagues.length" class="px-1 py-2 mb-0 text-xs text-n-slate-11">
      {{ t('OUTSIDER_VOICE.PHONE.TEAM_EMPTY') }}
    </p>
    <button
      v-for="person in colleagues"
      :key="person.id"
      type="button"
      class="flex items-center justify-between gap-2 px-2 py-1.5 text-left rounded-lg hover:bg-n-alpha-2 disabled:opacity-50"
      :disabled="!person.online"
      :title="
        person.online
          ? t('OUTSIDER_VOICE.PHONE.TEAM_ONLINE')
          : t('OUTSIDER_VOICE.PHONE.TEAM_OFFLINE')
      "
      data-testid="outsider-phone-team"
      @click="emit('pick', person.extension)"
    >
      <span class="flex items-center min-w-0 gap-2">
        <span class="relative shrink-0">
          <Avatar
            :name="person.name"
            :src="person.thumbnail"
            :size="24"
            rounded-full
          />
          <span
            class="absolute bottom-0 rounded-full size-2 ltr:right-0 rtl:left-0 outline outline-2 outline-n-alpha-3"
            :class="person.online ? 'bg-n-teal-9' : 'bg-n-slate-7'"
          />
        </span>
        <span class="flex flex-col min-w-0">
          <span class="text-sm truncate text-n-slate-12">
            {{ person.name }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{
              t('OUTSIDER_VOICE.PHONE.EXTENSION', {
                extension: person.extension,
              })
            }}
          </span>
        </span>
      </span>
      <Icon :icon="icon" class="size-4 shrink-0 text-n-slate-11" />
    </button>
  </div>
</template>
