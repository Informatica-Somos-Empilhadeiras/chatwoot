<script setup>
// OUTSIDER: por onde o cliente passou na URA antes de chegar (Entrega 26): o nome da URA, as opções que escolheu
// e o que digitou (CPF, pedido...). Aparece na ligação chegando e no telefone durante a conversa.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  // { flow, path: [{ title, answer }], vars }
  ivr: { type: Object, default: null },
  compact: { type: Boolean, default: false },
});

const { t } = useI18n();

const path = computed(() => props.ivr?.path || []);
</script>

<template>
  <div
    v-if="ivr && (path.length || ivr.flow)"
    class="flex flex-col gap-1.5 w-full"
    :class="compact ? 'items-center' : ''"
    data-testid="outsider-ivr-trail"
  >
    <span class="flex items-center gap-1.5 text-xs text-n-slate-11">
      <Icon icon="i-lucide-workflow" class="size-3.5" />
      {{ t('OUTSIDER_VOICE.IVR_TRAIL.TITLE', { flow: ivr.flow || '—' }) }}
    </span>
    <div
      v-if="path.length"
      class="flex flex-wrap gap-1"
      :class="compact ? 'justify-center' : ''"
    >
      <span
        v-for="(step, index) in path"
        :key="index"
        class="px-2 py-0.5 text-xs rounded-md bg-n-iris-3 text-n-iris-11"
      >
        <span class="opacity-80">{{ step.title }}:</span>
        {{ step.answer }}
      </span>
    </div>
  </div>
</template>
