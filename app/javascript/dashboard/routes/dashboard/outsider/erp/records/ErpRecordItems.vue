<script setup>
// OUTSIDER: os itens do painel de detalhe da seção ERP (ErpRecordPanel), logo abaixo do cliente: cada item com a
// descrição inteira, quantidade × unitário e total, e o rodapé com peças, serviços e total. Na OS, a conferência do
// estoque (Outsider::Erp::Orders::Conference): a situação da OS (não liberada, aguardando, conferindo, separada) e a de
// cada peça (conferida, parcial, aguardando; serviço não passa pela conferência), relida sozinha enquanto o estoque
// confere, e o botão "Liberar para separação" (o "Libera Conferência" do Mais Prático) com confirmação.
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ErpAPI from 'dashboard/api/outsider/erp';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { erpErrorMessage, formatMoney } from '../erpStore';
import { titleCase } from './recordsConfig';

const props = defineProps({
  items: { type: Array, default: () => [] },
  header: { type: Object, default: () => ({}) },
  company: { type: String, required: true },
  number: { type: Number, required: true },
  // só na OS; null quando o banco não tem a separação
  conference: { type: Object, default: null },
  canRelease: { type: Boolean, default: false },
});

const emit = defineEmits(['released']);

const { t, te } = useI18n();
const ct = (key, values) =>
  t(`OUTSIDER_ERP.RECORDS.CONFERENCE.${key}`, values || {});

// a conferência mostrada: a do detalhe, trocada pela releitura e pela resposta da liberação
const current = ref(props.conference);
watch(
  () => props.conference,
  value => {
    current.value = value;
  }
);
const state = computed(() => current.value?.state || '');

const qty = value => Number(value || 0).toLocaleString('pt-BR');
const parts = computed(() => props.items.filter(item => !item.servico));

const totals = computed(() => {
  const sum = list => list.reduce((acc, item) => acc + item.total, 0);
  return {
    parts: sum(parts.value),
    services: sum(props.items.filter(item => item.servico)),
    freight: Number(props.header.frete) || 0,
    discount: Number(props.header.desconto) || 0,
  };
});
// OS do aplicativo ou do chat fica sem total no ERP até o escritório salvar: soma dos itens
const total = computed(() => {
  const sum = totals.value;
  return (
    Number(props.header.total) ||
    sum.parts + sum.services + sum.freight - sum.discount
  );
});

// hora local (Brasília): "hoje às 09:20", "ontem às 15:19", "25/11 às 08:00"; o ERP às vezes só tem o dia
const ZONE = 'America/Sao_Paulo';
const dayKey = date => date.toLocaleDateString('pt-BR', { timeZone: ZONE });
const when = value => {
  const date = new Date(value);
  if (!value || Number.isNaN(date.getTime())) return '';
  const time = date.toLocaleTimeString('pt-BR', {
    timeZone: ZONE,
    hour: '2-digit',
    minute: '2-digit',
  });
  const today = new Date();
  const yesterday = new Date(today.getTime() - 86400000);
  let day = date.toLocaleDateString('pt-BR', {
    timeZone: ZONE,
    day: '2-digit',
    month: '2-digit',
  });
  if (dayKey(date) === dayKey(today)) day = ct('TODAY');
  else if (dayKey(date) === dayKey(yesterday)) day = ct('YESTERDAY');
  return time === '00:00' ? day : ct('AT', { day, time });
};

const duration = (from, to) => {
  const minutes = Math.round((new Date(to) - new Date(from)) / 60000);
  if (!(minutes >= 0)) return '';
  if (minutes < 60) return ct('MINUTES', { n: minutes });
  const hours = Math.floor(minutes / 60);
  if (hours < 24)
    return ct(minutes % 60 ? 'HOURS' : 'HOURS_EXACT', {
      h: hours,
      m: minutes % 60,
    });
  return ct('DAYS', { d: Math.floor(hours / 24), h: hours % 24 });
};

// a situação de cada peça; serviço não passa pela conferência
const itemState = item => {
  const c = current.value;
  if (!c || state.value === 'none') return null;
  if (item.servico)
    return { key: 'SKIP', class: 'bg-n-alpha-2 text-n-slate-10' };
  const row = (c.items || {})[String(item.item)] || {};
  const done = Number(row.conferido) || 0;
  const need = Number(item.quantidade) || 0;
  const count = `${qty(done)}/${qty(need)}`;
  const ok = { class: 'bg-n-teal-3 text-n-teal-11', icon: 'i-lucide-check' };
  if (need > 0 && done >= need) {
    const time =
      state.value === 'released' || state.value === 'conferring'
        ? when(row.at)
        : '';
    return { ...ok, key: 'COUNT', text: time ? `${count} · ${time}` : count };
  }
  if (done > 0)
    return { key: 'COUNT', text: count, class: 'bg-n-amber-3 text-n-amber-11' };
  if (state.value === 'done') return { ...ok, key: 'DONE' };
  if (state.value === 'partial')
    return { key: 'NOT_COUNTED', class: 'bg-n-ruby-3 text-n-ruby-11' };
  return { key: 'WAITING', class: 'bg-n-amber-3 text-n-amber-11' };
};

const counted = computed(
  () =>
    parts.value.filter(item => {
      const s = itemState(item);
      return s && s.class.includes('teal');
    }).length
);

const lastCounter = computed(() => {
  const log = current.value?.log || [];
  return titleCase(
    [...log].reverse().find(row => row.operacao === 'counted')?.name || ''
  );
});

const releasedLine = computed(() => {
  const c = current.value || {};
  const at = when(c.released_at);
  return c.released_by
    ? ct('RELEASED_BY', { when: at, name: c.released_by })
    : ct('RELEASED_ON', { when: at });
});

// o bloco de cima: ícone, cor, título e texto de cada situação
const summary = computed(() => {
  const c = current.value;
  if (!c) return null;
  const progress = ct('PROGRESS', {
    done: counted.value,
    total: parts.value.length,
  });
  switch (state.value) {
    case 'none':
      return {
        icon: 'i-lucide-clock',
        tone: 'bg-n-alpha-2 text-n-slate-11',
        title: ct('NONE'),
        text: parts.value.length
          ? ct('NONE_HINT', { n: parts.value.length })
          : ct('ONLY_SERVICES'),
      };
    case 'conferring':
      return {
        icon: 'i-lucide-package-search',
        tone: 'bg-n-amber-3 text-n-amber-11',
        title: ct('CONFERRING', { name: titleCase(c.by || '') }),
        text: `${releasedLine.value} · ${progress}`,
        bar: true,
      };
    case 'done':
    case 'partial':
      return {
        icon:
          state.value === 'done' ? 'i-lucide-check' : 'i-lucide-package-minus',
        tone:
          state.value === 'done'
            ? 'bg-n-teal-3 text-n-teal-11'
            : 'bg-n-amber-3 text-n-amber-11',
        title: ct(
          `${state.value === 'done' ? 'DONE' : 'PARTIAL'}${lastCounter.value ? '_BY' : ''}`,
          { when: when(c.done_at), name: lastCounter.value }
        ),
        text: [duration(c.released_at, c.done_at), progress]
          .filter(Boolean)
          .join(' · '),
      };
    default:
      return {
        icon: 'i-lucide-package',
        tone: 'bg-n-amber-3 text-n-amber-11',
        title: ct('WAITING_STOCK'),
        text: `${releasedLine.value} · ${progress}`,
        bar: true,
      };
  }
});

const CHIP = {
  none: ['NOT_RELEASED', 'bg-n-alpha-2 text-n-slate-11'],
  released: ['CHIP_WAITING', 'bg-n-amber-3 text-n-amber-11'],
  conferring: ['CHIP_CONFERRING', 'bg-n-amber-3 text-n-amber-11'],
  done: ['CHIP_DONE', 'bg-n-teal-3 text-n-teal-11'],
  partial: ['CHIP_PARTIAL', 'bg-n-amber-3 text-n-amber-11'],
};
const chip = computed(() => CHIP[state.value]);
const showRelease = computed(
  () => state.value === 'none' && props.canRelease && parts.value.length > 0
);

// liberar: confirma, grava e mostra a conferência que voltou
const confirming = ref(false);
const releasing = ref(false);
const release = async () => {
  releasing.value = true;
  try {
    const { data } = await ErpAPI.releaseOrder(props.company, props.number);
    current.value = data.conference;
    confirming.value = false;
    useAlert(ct('RELEASED', { number: props.number }));
    emit('released');
  } catch (error) {
    const data = error?.response?.data || {};
    const key = `OUTSIDER_ERP.RECORDS.CONFERENCE.ERRORS.${String(data.reason || data.error).toUpperCase()}`;
    useAlert(te(key) ? t(key) : erpErrorMessage(t, error));
  } finally {
    releasing.value = false;
  }
};

// enquanto o estoque confere, relê a cada 45 s (só a conferência)
let timer = null;
const stop = () => {
  if (timer) clearInterval(timer);
  timer = null;
};
const poll = async () => {
  if (document.hidden) return;
  try {
    const { data } = await ErpAPI.orderConference(props.company, props.number);
    if (data.conference) current.value = data.conference;
  } catch {
    // fora do ar: fica o que já está na tela
  }
};
watch(
  state,
  value => {
    stop();
    if (value === 'released' || value === 'conferring')
      timer = setInterval(poll, 45000);
  },
  { immediate: true }
);
onBeforeUnmount(stop);

const LABEL =
  'text-[11px] font-medium uppercase tracking-wider text-n-slate-10';
</script>

<template>
  <section class="flex flex-col gap-2" data-erp-record-items>
    <span v-if="!items.length" :class="LABEL">
      {{ t('OUTSIDER_ERP.RECORDS.ITEMS', { count: 0 }) }}
    </span>
    <p v-if="!items.length" class="mb-0 text-xs text-n-slate-10">
      {{ t('OUTSIDER_ERP.RECORDS.NO_ITEMS') }}
    </p>

    <div
      v-else
      class="overflow-hidden rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
    >
      <div
        class="flex items-center justify-between gap-2 px-3 py-2.5 border-b bg-n-alpha-1 border-n-weak"
      >
        <span class="text-[13px] font-semibold text-n-slate-12">
          {{ ct('TITLE') }}
          <span class="font-normal text-n-slate-11">· {{ items.length }}</span>
        </span>
        <Button
          v-if="showRelease && !confirming"
          size="sm"
          icon="i-lucide-package-plus"
          :label="ct('RELEASE')"
          data-erp-release-order
          @click="confirming = true"
        />
        <span
          v-else-if="
            chip && current && !confirming && (state !== 'none' || canRelease)
          "
          class="px-2 py-0.5 text-[11px] font-medium rounded-full"
          :class="chip[1]"
          data-erp-conference-chip
        >
          {{ ct(chip[0]) }}
        </span>
      </div>

      <div
        v-if="confirming"
        class="flex flex-col gap-2 px-3 py-3 border-b bg-n-teal-2 border-n-weak"
        data-erp-release-confirm
      >
        <span class="text-[13px] font-semibold text-n-slate-12">
          {{ ct('CONFIRM_TITLE', { number }) }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ ct('CONFIRM_TEXT', { n: parts.length }) }}
        </span>
        <div class="flex justify-end gap-2">
          <Button
            size="sm"
            variant="faded"
            color="slate"
            :label="t('OUTSIDER_ERP.CANCEL')"
            :disabled="releasing"
            @click="confirming = false"
          />
          <Button
            size="sm"
            icon="i-lucide-package-plus"
            :label="ct('RELEASE')"
            :is-loading="releasing"
            data-erp-release-confirm-button
            @click="release"
          />
        </div>
      </div>

      <div
        v-if="summary"
        class="flex items-start gap-2.5 px-3 py-2.5 border-b border-n-weak"
        :data-erp-conference="state"
      >
        <span
          class="grid rounded-lg size-7 shrink-0 place-content-center"
          :class="summary.tone"
        >
          <Icon :icon="summary.icon" class="size-4" />
        </span>
        <div class="flex flex-col flex-1 min-w-0 gap-0.5">
          <span class="text-[13px] font-semibold text-n-slate-12">
            {{ summary.title }}
          </span>
          <span class="text-xs text-n-slate-11">{{ summary.text }}</span>
          <div
            v-if="summary.bar && parts.length"
            class="h-1.5 mt-1 overflow-hidden rounded-full bg-n-alpha-2"
          >
            <div
              class="h-full rounded-full bg-n-amber-9"
              :style="{ width: `${(counted / parts.length) * 100}%` }"
            />
          </div>
        </div>
      </div>

      <div
        v-for="(item, index) in items"
        :key="`${item.codigo}-${index}`"
        class="flex items-start gap-3 px-3 py-2.5 border-b border-n-weak last:border-0"
        data-erp-record-item
      >
        <span class="w-10 pt-px text-xs tabular-nums shrink-0 text-n-slate-10">
          {{ item.codigo }}
        </span>
        <div class="flex flex-col flex-1 min-w-0 gap-1">
          <span class="text-[13px] leading-snug text-n-slate-12 break-words">
            {{ item.descricao }}
          </span>
          <span
            class="flex flex-wrap items-center gap-1.5 text-xs tabular-nums text-n-slate-11"
          >
            <span
              class="px-1.5 py-px text-[10px] font-semibold rounded"
              :class="
                item.servico
                  ? 'bg-n-blue-3 text-n-blue-11'
                  : 'bg-n-alpha-2 text-n-slate-11'
              "
            >
              {{
                item.servico ? t('OUTSIDER_ERP.RECORDS.SERVICE') : ct('PART')
              }}
            </span>
            {{
              `${qty(item.quantidade)}${item.unidade ? ` ${item.unidade.toLowerCase()}` : ''} × ${formatMoney(item.unitario)}`
            }}
            <span v-if="item.desconto" class="text-n-ruby-11">
              {{ `−${qty(item.desconto)}%` }}
            </span>
          </span>
        </div>
        <div class="flex flex-col items-end gap-1 shrink-0">
          <span class="text-[13px] font-semibold tabular-nums text-n-slate-12">
            {{ formatMoney(item.total) }}
          </span>
          <span
            v-if="itemState(item)"
            class="flex items-center gap-1 px-2 py-px text-[11px] font-medium rounded-full whitespace-nowrap"
            :class="itemState(item).class"
            data-erp-item-conference
          >
            <Icon
              v-if="itemState(item).icon"
              :icon="itemState(item).icon"
              class="size-3"
            />
            {{
              itemState(item).key === 'COUNT'
                ? itemState(item).text
                : ct(`ITEM.${itemState(item).key}`)
            }}
          </span>
        </div>
      </div>

      <div
        class="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 px-3 py-2.5 text-xs border-t bg-n-alpha-1 border-n-weak text-n-slate-11"
      >
        <span class="flex flex-wrap gap-x-2">
          <span v-if="totals.services">
            {{ t('OUTSIDER_ERP.BUDGET.TOTALS.PARTS') }}
            <b class="font-semibold tabular-nums text-n-slate-12">
              {{ formatMoney(totals.parts) }}
            </b>
          </span>
          <span v-if="totals.services">
            {{ t('OUTSIDER_ERP.BUDGET.TOTALS.SERVICES') }}
            <b class="font-semibold tabular-nums text-n-slate-12">
              {{ formatMoney(totals.services) }}
            </b>
          </span>
          <span v-if="totals.freight">
            {{ t('OUTSIDER_ERP.BUDGET.TOTALS.FREIGHT') }}
            <b class="font-semibold tabular-nums text-n-slate-12">
              {{ formatMoney(totals.freight) }}
            </b>
          </span>
          <span v-if="totals.discount">
            {{ t('OUTSIDER_ERP.BUDGET.TOTALS.DISCOUNTS') }}
            <b class="font-semibold tabular-nums text-n-ruby-11">
              {{ `− ${formatMoney(totals.discount)}` }}
            </b>
          </span>
        </span>
        <span class="ml-auto text-[13px]">
          {{ t('OUTSIDER_ERP.BUDGET.TOTALS.TOTAL') }}
          <b class="font-semibold tabular-nums text-n-slate-12">
            {{ formatMoney(total) }}
          </b>
        </span>
      </div>
    </div>
  </section>
</template>
