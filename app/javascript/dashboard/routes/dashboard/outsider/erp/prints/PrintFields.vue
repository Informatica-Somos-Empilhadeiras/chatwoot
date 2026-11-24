<script setup>
// OUTSIDER: aba Campos do estúdio: para cada grupo (Dados da OS, Cliente, Equipamento...) e cada tabela (Produtos,
// Itens, Respostas do checklist), quais campos/colunas aparecem e em que ordem (arrastar). Vale para todos os blocos
// daquele grupo/tabela no modelo.
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const props = defineProps({
  catalog: { type: Object, required: true },
  focus: { type: String, default: '' },
});

const fields = defineModel('fields', { type: Object, required: true });

const { t } = useI18n();

const lists = computed(() => [
  ...(props.catalog.groups || []).map(group => ({
    key: group.key,
    label: group.label,
    known: group.fields,
    table: false,
  })),
  ...(props.catalog.tables || []).map(table => ({
    key: table.key,
    label: table.label,
    known: table.columns,
    table: true,
  })),
]);

const open = ref({});
const root = ref(null);

watch(
  () => props.focus,
  async key => {
    if (!key) return;
    open.value = { ...open.value, [key]: true };
    await nextTick();
    root.value
      ?.querySelector(`[data-field-list="${key}"]`)
      ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  },
  { immediate: true }
);

const itemsOf = list =>
  (
    fields.value[list.key] || list.known.map(f => ({ key: f.key, on: f.on }))
  ).map(item => ({
    ...item,
    label: list.known.find(f => f.key === item.key)?.label || item.key,
  }));

const setItems = (list, items) => {
  fields.value = {
    ...fields.value,
    [list.key]: items.map(item => ({ key: item.key, on: item.on })),
  };
};

const toggle = (list, key, on) =>
  setItems(
    list,
    itemsOf(list).map(item => (item.key === key ? { ...item, on } : item))
  );

const countOn = list => itemsOf(list).filter(item => item.on).length;
</script>

<template>
  <div ref="root" class="flex flex-col gap-3">
    <p class="mb-0 text-xs text-n-slate-11">
      {{ t('OUTSIDER_ERP.PRINTS.STUDIO.FIELDS_HELP') }}
    </p>
    <section
      v-for="list in lists"
      :key="list.key"
      class="rounded-xl outline outline-1 -outline-offset-1"
      :class="focus === list.key ? 'outline-n-teal-8' : 'outline-n-weak'"
      :data-field-list="list.key"
    >
      <button
        type="button"
        class="flex items-center justify-between w-full gap-2 px-3 py-2.5 text-left"
        @click="open = { ...open, [list.key]: !open[list.key] }"
      >
        <span
          class="flex items-center gap-2 text-sm font-medium text-n-slate-12"
        >
          <span
            :class="list.table ? 'i-lucide-table' : 'i-lucide-layout-grid'"
            class="size-4 text-n-slate-10"
          />
          {{ list.label }}
        </span>
        <span class="flex items-center gap-2 text-xs text-n-slate-10">
          {{
            t('OUTSIDER_ERP.PRINTS.STUDIO.FIELDS_COUNT', {
              on: countOn(list),
              total: list.known.length,
            })
          }}
          <span
            :class="
              open[list.key] ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
            "
            class="size-4"
          />
        </span>
      </button>
      <Draggable
        v-if="open[list.key]"
        :model-value="itemsOf(list)"
        item-key="key"
        handle="[data-field-handle]"
        :animation="150"
        class="flex flex-col gap-1 px-2 pb-2"
        @update:model-value="items => setItems(list, items)"
      >
        <template #item="{ element }">
          <div
            class="flex items-center gap-2 px-2 py-1.5 rounded-lg bg-n-alpha-1"
            :class="{ 'opacity-60': !element.on }"
          >
            <span
              data-field-handle
              class="i-lucide-grip-vertical size-4 text-n-slate-9 cursor-grab"
            />
            <span class="flex-1 text-sm truncate text-n-slate-12">
              {{ element.label }}
            </span>
            <Switch
              :model-value="element.on"
              @update:model-value="on => toggle(list, element.key, on)"
            />
          </div>
        </template>
      </Draggable>
    </section>
  </div>
</template>
