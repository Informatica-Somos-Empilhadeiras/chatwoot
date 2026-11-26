<script setup>
// OUTSIDER: a OS feita no chat depois de gravada: o número oficial do Mais Prático e o que foi lido de volta do ERP
// (cabeçalho, histórico, peças e serviços, orçamento fechado, app do técnico e sub status), passo a passo. Cancelada:
// o aviso de que a situação virou CANCELADA (nada foi apagado). Os botões ficam com quem mostra (gaveta ou conversão).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { formatMoney, formatDate } from '../erpStore';

const props = defineProps({
  draft: { type: Object, required: true },
});

const { t } = useI18n();

const readback = computed(() => props.draft.readback || {});
const fields = computed(() => props.draft.fields || {});
const steps = computed(() => props.draft.steps || []);
const isConversion = computed(() => props.draft.kind === 'conversion');

const subtitle = computed(() =>
  [
    [props.draft.customer_code, props.draft.customer_name]
      .filter(Boolean)
      .join(' · '),
    fields.value.maquina_descricao,
    (readback.value.serie || fields.value.serie) &&
      t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.SERIAL', {
        value: readback.value.serie || fields.value.serie,
      }),
  ]
    .filter(Boolean)
    .join(' · ')
);

// cada linha: ok (o que foi lido de volta confere), texto e o detalhe à direita
const rows = computed(() => {
  const back = readback.value;
  const list = [];
  const header = [back.situacao, back.tipo].filter(Boolean).join(', ');
  list.push({
    key: 'header',
    ok: !!back.situacao,
    text: t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.HEADER', {
      detail: header,
    }),
    detail: t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.READ_BACK'),
  });
  list.push({
    key: 'history',
    ok: Number(back.historico) >= 2,
    text: t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.HISTORY'),
    detail: t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.HISTORY_LINES', {
      count: Number(back.historico) || 0,
    }),
  });
  list.push({
    key: 'items',
    ok:
      Number(back.itens_esperados) > 0 &&
      Number(back.itens) >= Number(back.itens_esperados),
    text: t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.ITEMS'),
    detail: t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.ITEMS_COUNT', {
      count: Number(back.itens) || 0,
      total: Number(back.itens_esperados) || 0,
    }),
  });
  if (isConversion.value)
    list.push({
      key: 'quote',
      ok:
        steps.value.includes('orcamento_fechado') &&
        Number(back.orcamento) === Number(props.draft.quote_number),
      text: t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.QUOTE_CLOSED', {
        number: props.draft.quote_number,
      }),
      detail: t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.BOTH_WAYS'),
    });
  if (fields.value.agendar)
    list.push({
      key: 'schedule',
      ok: steps.value.includes('agendado'),
      text: steps.value.includes('agendado')
        ? t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.SCHEDULED')
        : t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.SCHEDULE_FAILED'),
      detail: t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.OFFICIAL_ROUTE'),
    });
  return list;
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <div
      class="flex items-center gap-4 p-4 border rounded-xl"
      :class="
        draft.cancelled
          ? 'bg-n-alpha-1 border-n-weak'
          : 'bg-n-teal-2 border-n-teal-6'
      "
    >
      <span
        class="flex items-center justify-center rounded-full shrink-0 size-11"
        :class="
          draft.cancelled
            ? 'bg-n-slate-4 text-n-slate-11'
            : 'bg-n-teal-9 text-white'
        "
      >
        <Icon
          :icon="draft.cancelled ? 'i-lucide-ban' : 'i-lucide-check'"
          class="size-6"
        />
      </span>
      <div class="flex flex-col min-w-0 gap-0.5">
        <strong class="text-lg text-n-slate-12" data-erp-order-recorded>
          {{
            draft.cancelled
              ? t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.CANCELLED', {
                  number: draft.erp_number,
                })
              : t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.RECORDED', {
                  number: draft.erp_number,
                })
          }}
        </strong>
        <span class="text-sm text-n-slate-11">{{ subtitle }}</span>
        <span v-if="draft.cancelled" class="text-xs text-n-slate-10">
          {{
            t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.CANCELLED_HINT', {
              date: formatDate(draft.cancelled_at),
            })
          }}
        </span>
      </div>
    </div>

    <section class="flex flex-col">
      <span
        class="pb-1 text-[11px] font-medium tracking-wide uppercase text-n-slate-10"
      >
        {{ t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.CHECKED') }}
      </span>
      <div
        v-for="row in rows"
        :key="row.key"
        class="flex items-center gap-3 py-2 text-sm border-b border-n-weak"
      >
        <span
          class="flex items-center justify-center rounded-full shrink-0 size-5"
          :class="
            row.ok
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-amber-3 text-n-amber-11'
          "
        >
          <Icon
            :icon="row.ok ? 'i-lucide-check' : 'i-lucide-triangle-alert'"
            class="size-3"
          />
        </span>
        <span class="flex-1 min-w-0 text-n-slate-12">{{ row.text }}</span>
        <span v-if="row.detail" class="text-xs shrink-0 text-n-slate-10">
          {{ row.detail }}
        </span>
      </div>
    </section>

    <p
      v-if="!draft.cancelled"
      class="p-3 mb-0 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
    >
      {{
        isConversion
          ? t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.NEXT_CONVERSION', {
              number: draft.quote_number,
              os: draft.erp_number,
            })
          : t('OUTSIDER_ERP.ORDER_DRAFT.RESULT.NEXT_FRESH', {
              number: draft.erp_number,
              total: formatMoney(draft.total),
            })
      }}
    </p>
  </div>
</template>
