<script setup>
// OUTSIDER: o que dá para fazer com a situação da proposta (Entrega 20). O próximo passo natural fica à
// vista (enviada: o cliente aceitou ou recusou); o resto, inclusive cancelar e apagar, fica no menu
// "Mais ações", longe do botão de enviar, para ninguém cancelar sem querer.
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const props = defineProps({
  status: { type: String, default: 'draft' },
  canEdit: { type: Boolean, default: false },
  canDelete: { type: Boolean, default: false },
});

const emit = defineEmits(['change', 'delete']);

const { t } = useI18n();
const menuOpen = ref(false);

// situações seguintes possíveis a partir da atual (as mesmas que o servidor aceita)
const NEXT = {
  draft: ['sent', 'canceled'],
  sent: ['accepted', 'rejected', 'canceled'],
  accepted: ['draft'],
  rejected: ['draft'],
  canceled: ['draft'],
};

const ICONS = {
  sent: 'i-lucide-send',
  accepted: 'i-lucide-circle-check',
  rejected: 'i-lucide-circle-x',
  canceled: 'i-lucide-ban',
  draft: 'i-lucide-undo-2',
};

const next = computed(() => (props.canEdit ? NEXT[props.status] || [] : []));

// enviada: aceitou e recusou ficam à vista
const visible = computed(() =>
  next.value.filter(status => ['accepted', 'rejected'].includes(status))
);

const menuItems = computed(() => [
  ...next.value
    .filter(status => !visible.value.includes(status))
    .map(status => ({
      action: 'status',
      value: status,
      label: t(`OUTSIDER_CRM.PROPOSALS.ACTIONS.${status.toUpperCase()}`),
      icon: ICONS[status],
    })),
  ...(props.canDelete
    ? [
        {
          action: 'delete',
          value: 'delete',
          label: t('OUTSIDER_CRM.DELETE.CONFIRM'),
          icon: 'i-lucide-trash-2',
        },
      ]
    : []),
]);

const onMenu = ({ action, value }) => {
  menuOpen.value = false;
  if (action === 'delete') emit('delete');
  else emit('change', value);
};
</script>

<template>
  <div class="flex flex-wrap items-center gap-2">
    <Button
      v-for="status in visible"
      :key="status"
      size="sm"
      variant="faded"
      :color="status === 'accepted' ? 'teal' : 'ruby'"
      :icon="ICONS[status]"
      :label="t(`OUTSIDER_CRM.PROPOSALS.ACTIONS.CUSTOMER_${status.toUpperCase()}`)"
      @click="emit('change', status)"
    />
    <div v-if="menuItems.length" class="relative">
      <Button
        size="sm"
        variant="ghost"
        color="slate"
        icon="i-lucide-ellipsis"
        :label="t('OUTSIDER_CRM.PROPOSALS.ACTIONS.MORE')"
        @click="menuOpen = !menuOpen"
      />
      <DropdownMenu
        v-if="menuOpen"
        v-on-click-outside="() => (menuOpen = false)"
        :menu-items="menuItems"
        class="top-full mt-1 ltr:right-0 rtl:left-0 min-w-52 z-30"
        @action="onMenu"
      />
    </div>
  </div>
</template>
