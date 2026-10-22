<script setup>
// OUTSIDER: moldura de um bloco na folha do editor (Entrega 17), no jeito da Brevo: ao passar o mouse,
// contorno tracejado e a etiqueta com o nome do bloco (que também é a alça para arrastar); selecionado,
// contorno cheio e a barra de ações: subir, descer, duplicar e apagar (blocos livres) ou esconder
// (blocos da proposta, que voltam pela lista de blocos).
import { useI18n } from 'vue-i18n';

defineProps({
  name: { type: String, required: true },
  icon: { type: String, default: '' },
  selected: { type: Boolean, default: false },
  free: { type: Boolean, default: false },
  first: { type: Boolean, default: false },
  last: { type: Boolean, default: false },
  newPage: { type: Boolean, default: false },
});

const emit = defineEmits(['select', 'move', 'duplicate', 'hide', 'remove']);

const { t } = useI18n();

const ACTION =
  'grid size-6 place-content-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:opacity-40 disabled:pointer-events-none';
</script>

<template>
  <div
    class="relative group/block rounded-sm"
    :class="
      selected
        ? 'outline outline-2 outline-offset-2 outline-n-brand z-10'
        : 'hover:outline hover:outline-1 hover:outline-dashed hover:outline-offset-2 hover:outline-n-brand'
    "
    data-canvas-block
    @click.stop="emit('select')"
  >
    <span
      class="crm-canvas-handle absolute z-20 items-center gap-1 px-1.5 py-0.5 text-[11px] font-medium leading-4 rounded-md cursor-grab -top-[1.15rem] -left-1 whitespace-nowrap shadow-sm"
      :class="
        selected
          ? 'flex bg-n-brand text-white'
          : 'hidden group-hover/block:flex bg-n-solid-1 text-n-blue-11 outline outline-1 outline-n-brand'
      "
      :title="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.DRAG')"
      data-block-chip
    >
      <span class="i-lucide-grip-vertical size-3" />
      <span v-if="icon" :class="icon" class="size-3" />
      {{ name }}
      <span
        v-if="newPage"
        class="px-1 ml-0.5 rounded bg-white/25"
      >
        {{ t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.NEW_PAGE_BADGE') }}
      </span>
    </span>
    <div
      v-if="selected"
      class="absolute z-20 flex items-center gap-0.5 p-0.5 rounded-lg shadow-md -top-[1.6rem] right-0 bg-n-solid-1 outline outline-1 outline-n-weak"
      data-block-toolbar
      @click.stop
    >
      <button
        v-tooltip.top="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.MOVE_UP')"
        type="button"
        :class="ACTION"
        :disabled="first"
        :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.MOVE_UP')"
        @click="emit('move', -1)"
      >
        <span class="i-lucide-arrow-up size-3.5" />
      </button>
      <button
        v-tooltip.top="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.MOVE_DOWN')"
        type="button"
        :class="ACTION"
        :disabled="last"
        :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.MOVE_DOWN')"
        @click="emit('move', 1)"
      >
        <span class="i-lucide-arrow-down size-3.5" />
      </button>
      <button
        v-if="free"
        v-tooltip.top="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.DUPLICATE')"
        type="button"
        :class="ACTION"
        :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.STUDIO.DUPLICATE')"
        data-block-duplicate
        @click="emit('duplicate')"
      >
        <span class="i-lucide-copy size-3.5" />
      </button>
      <button
        v-if="free"
        v-tooltip.top="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.REMOVE')"
        type="button"
        :class="ACTION"
        class="hover:!text-n-ruby-11"
        :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.REMOVE')"
        data-block-remove
        @click="emit('remove')"
      >
        <span class="i-lucide-trash-2 size-3.5" />
      </button>
      <button
        v-else
        v-tooltip.top="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.HIDE')"
        type="button"
        :class="ACTION"
        :aria-label="t('OUTSIDER_CRM.PROPOSAL_SETTINGS.BLOCKS.HIDE')"
        data-block-hide
        @click="emit('hide')"
      >
        <span class="i-lucide-eye-off size-3.5" />
      </button>
    </div>
    <slot />
  </div>
</template>
