<script setup>
// OUTSIDER: Kanban de um pipeline. Colunas são as etapas abertas; arrastar troca etapa e ordem
// (PATCH /move). Soltar em Ganho ou Perdido fecha o negócio; Perdido pede o motivo.
// Cards de outros vendedores aparecem com cadeado e não se movem (a API também recusa).
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import OpportunityCard from './OpportunityCard.vue';
import LostReasonDialog from './LostReasonDialog.vue';
import { STAGE_COLORS, errorMessage, formatMoney } from '../helpers';

const props = defineProps({
  access: { type: Object, required: true },
  pipeline: { type: Object, required: true },
  filters: { type: Object, required: true },
  lostReasons: { type: Array, required: true },
});

const emit = defineEmits(['open', 'new', 'changed']);

const { t } = useI18n();

const isLoading = ref(false);
const isDragging = ref(false);
const columns = ref([]);
// listas comuns (não reativas) de propósito: a área recebe o card e é esvaziada sem re-renderizar,
// o que evita o erro do vuedraggable ao montar um item numa lista escondida
const wonZone = [];
const lostZone = [];
const lostDialogRef = ref(null);

const canCreate = computed(() =>
  props.access.units.some(unit => unit.id === props.pipeline.business_unit_id)
);

const columnColor = (stage, index) =>
  stage.color || STAGE_COLORS[index % STAGE_COLORS.length];

const load = async () => {
  isLoading.value = true;
  try {
    const params = { pipeline_id: props.pipeline.id };
    if (props.filters.owner_id) params.owner_id = props.filters.owner_id;
    if (props.filters.q) params.q = props.filters.q;
    const { data } = await CrmAPI.getBoard(params);
    columns.value = data.stages;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

const fail = error => {
  useAlert(errorMessage(t, error));
  load();
};

const persistMove = async (opportunity, column, index) => {
  try {
    const { data } = await CrmAPI.moveOpportunity(
      opportunity.id,
      column.id,
      index
    );
    Object.assign(opportunity, data);
    emit('changed');
  } catch (error) {
    fail(error);
  }
};

const onColumnChange = (column, event) => {
  if (event.added) {
    const { element, newIndex } = event.added;
    column.count += 1;
    column.total_cents += element.value_cents;
    persistMove(element, column, newIndex);
  }
  if (event.removed) {
    column.count -= 1;
    column.total_cents -= event.removed.element.value_cents;
  }
  if (event.moved) {
    persistMove(event.moved.element, column, event.moved.newIndex);
  }
};

const close = async (opportunity, status, lostReasonId = null) => {
  try {
    await CrmAPI.updateOpportunity(opportunity.id, {
      status,
      lost_reason_id: lostReasonId,
    });
    useAlert(
      t(`OUTSIDER_CRM.BOARD.${status === 'won' ? 'WON_DONE' : 'LOST_DONE'}`, {
        title: opportunity.title,
      })
    );
    emit('changed');
  } catch (error) {
    fail(error);
  }
};

const onWonDrop = event => {
  if (!event.added) return;
  wonZone.splice(0);
  close(event.added.element, 'won');
};

const onLostDrop = event => {
  if (!event.added) return;
  lostZone.splice(0);
  lostDialogRef.value?.open(event.added.element);
};

const canMove = ({ draggedContext }) => !!draggedContext.element.can_edit;

watch(
  () => [props.pipeline.id, props.filters.owner_id, props.filters.q],
  load,
  { immediate: true }
);

defineExpose({ reload: load });
</script>

<template>
  <div class="relative">
    <div
      v-if="isLoading && !columns.length"
      class="flex justify-center p-8 text-n-slate-10"
    >
      <Spinner />
    </div>

    <div class="flex items-start gap-3 pb-4 overflow-x-auto">
      <div
        v-for="(column, index) in columns"
        :key="column.id"
        class="flex flex-col shrink-0 w-72 rounded-xl bg-n-alpha-1 outline outline-1 -outline-offset-1 outline-n-container"
      >
        <div
          class="h-1 rounded-t-xl"
          :style="{ backgroundColor: columnColor(column, index) }"
        />
        <div class="flex flex-col gap-0.5 px-3 pt-2.5 pb-2">
          <div class="flex items-center justify-between gap-2">
            <span class="font-medium truncate text-n-slate-12">
              {{ column.name }}
            </span>
            <span
              class="px-1.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
            >
              {{ column.count }}
            </span>
          </div>
          <span class="text-xs text-n-slate-11">
            {{ formatMoney(column.total_cents) }}
            <template v-if="column.sla_hours">
              ·
              {{
                t('OUTSIDER_CRM.BOARD.SLA_HOURS', { hours: column.sla_hours })
              }}
            </template>
          </span>
        </div>

        <Draggable
          :list="column.opportunities"
          item-key="id"
          group="crm-board"
          :animation="150"
          :move="canMove"
          filter=".crm-locked"
          :prevent-on-filter="false"
          ghost-class="opacity-40"
          class="flex flex-col gap-2 px-2 pb-2 overflow-y-auto min-h-24 max-h-[calc(100vh-22rem)]"
          @start="isDragging = true"
          @end="isDragging = false"
          @change="event => onColumnChange(column, event)"
        >
          <template #item="{ element }">
            <OpportunityCard
              :opportunity="element"
              :class="{ 'crm-locked': !element.can_edit }"
              @click="emit('open', element)"
            />
          </template>
        </Draggable>

        <p
          v-if="column.count > column.opportunities.length"
          class="px-3 pb-2 mb-0 text-xs text-n-slate-10"
        >
          {{
            t('OUTSIDER_CRM.BOARD.HIDDEN', {
              count: column.count - column.opportunities.length,
            })
          }}
        </p>

        <div v-if="canCreate" class="px-2 pb-2">
          <Button
            type="button"
            icon="i-lucide-plus"
            size="sm"
            variant="ghost"
            color="slate"
            class="w-full !justify-start"
            :label="t('OUTSIDER_CRM.BOARD.ADD')"
            @click="emit('new', column)"
          />
        </div>
      </div>

      <p
        v-if="!isLoading && !columns.length"
        class="p-6 mb-0 text-sm text-n-slate-11"
      >
        {{ t('OUTSIDER_CRM.BOARD.NO_STAGES') }}
      </p>
    </div>

    <div
      class="fixed z-40 flex gap-3 p-3 transition-all duration-200 -translate-x-1/2 shadow-xl bottom-4 left-1/2 rounded-2xl bg-n-alpha-3 backdrop-blur-[100px]"
      :class="
        isDragging
          ? 'opacity-100 translate-y-0'
          : 'opacity-0 translate-y-8 pointer-events-none'
      "
    >
      <div
        class="relative flex items-center justify-center gap-2 w-56 h-16 text-sm font-medium border-2 border-dashed rounded-xl border-n-teal-8 text-n-teal-11 bg-n-teal-2"
      >
        <Icon icon="i-lucide-trophy" class="size-4" />
        {{ t('OUTSIDER_CRM.BOARD.DROP_WON') }}
        <Draggable
          :list="wonZone"
          item-key="id"
          :group="{ name: 'crm-board', pull: false, put: true }"
          class="absolute inset-0 overflow-hidden opacity-0"
          @change="onWonDrop"
        >
          <template #item>
            <div />
          </template>
        </Draggable>
      </div>
      <div
        class="relative flex items-center justify-center gap-2 w-56 h-16 text-sm font-medium border-2 border-dashed rounded-xl border-n-ruby-8 text-n-ruby-11 bg-n-ruby-2"
      >
        <Icon icon="i-lucide-circle-x" class="size-4" />
        {{ t('OUTSIDER_CRM.BOARD.DROP_LOST') }}
        <Draggable
          :list="lostZone"
          item-key="id"
          :group="{ name: 'crm-board', pull: false, put: true }"
          class="absolute inset-0 overflow-hidden opacity-0"
          @change="onLostDrop"
        >
          <template #item>
            <div />
          </template>
        </Draggable>
      </div>
    </div>

    <LostReasonDialog
      ref="lostDialogRef"
      :lost-reasons="lostReasons"
      @confirm="(opportunity, reasonId) => close(opportunity, 'lost', reasonId)"
      @cancel="load"
    />
  </div>
</template>
