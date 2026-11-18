<script setup>
// OUTSIDER: aviso por cima do chat/canal enquanto a pessoa arrasta arquivos para anexar (useTeamsDrop.js).
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const { t } = useI18n();
</script>

<template>
  <div
    class="absolute inset-0 z-40 flex items-center justify-center p-6 pointer-events-none bg-n-surface-1/80 backdrop-blur-[2px]"
    data-teams-drop
  >
    <div
      class="flex flex-col items-center gap-2 px-10 py-8 text-center border-2 border-dashed rounded-2xl tms-border tms-soft"
    >
      <Icon icon="i-lucide-upload" class="size-8" />
      <b class="text-base">{{ t('OUTSIDER_TEAMS_AREA.DROP.TITLE') }}</b>
      <span class="text-xs opacity-80">
        {{ t('OUTSIDER_TEAMS_AREA.DROP.HINT') }}
      </span>
    </div>
  </div>
</template>
