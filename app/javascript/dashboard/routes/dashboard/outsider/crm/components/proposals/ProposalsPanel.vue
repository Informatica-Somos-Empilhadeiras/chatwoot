<script setup>
// OUTSIDER: CRM > Propostas. Lista com busca (número, cliente, contato, máquina) e filtros; cada um vê
// as próprias, o administrador vê todas e libera para os agentes em Configurações > Propostas.
// ?proposta=<id> abre a proposta e ?proposta=nova (com contato, negocio, tipo e produto) abre uma nova.
// Entrega 20 (mais simples): a situação é escolhida em botões de um clique; tipo, vendedor e datas ficam
// em "Mais filtros"; a tabela junta cliente e título numa coluna e situação e validade em outra.
import { ref, computed, watch, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ProposalEditor from './ProposalEditor.vue';
import ProposalPdfDialog from './ProposalPdfDialog.vue';
import { errorMessage, formatDate, formatMoney } from '../../helpers';
import { PROPOSAL_STATUSES, PROPOSAL_STATUS_COLORS } from './proposalHelpers';

const props = defineProps({
  access: { type: Object, required: true },
  pipelines: { type: Array, required: true },
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const agents = useMapGetter('agents/getAgents');

const proposals = ref([]);
const meta = ref({ count: 0, total_cents: 0, page: 1, per_page: 30 });
const isLoading = ref(false);
const searchText = ref('');
const filters = ref({ status: '', kind: '', owner_id: '', from: '', to: '' });
const pdfRef = ref(null);
const showMoreFilters = ref(false);

// filtros recolhidos que estão em uso: o botão "Mais filtros" mostra quantos
const moreFiltersCount = computed(
  () =>
    ['kind', 'owner_id', 'from', 'to'].filter(key => filters.value[key] !== '')
      .length
);

const openId = computed(() => route.query.proposta || null);

const canSeeOthers = computed(() => props.access.proposals?.view_all);

const statusOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.PROPOSALS.FILTERS.ALL') },
  ...PROPOSAL_STATUSES.map(status => ({
    value: status,
    label: t(`OUTSIDER_CRM.PROPOSALS.FILTERS.STATUS.${status.toUpperCase()}`),
  })),
]);

const kindOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.PROPOSALS.FILTERS.ALL_KINDS') },
  { value: 'sale', label: t('OUTSIDER_CRM.PROPOSALS.KIND.SALE') },
  { value: 'rental', label: t('OUTSIDER_CRM.PROPOSALS.KIND.RENTAL') },
]);

const ownerOptions = computed(() => [
  { value: '', label: t('OUTSIDER_CRM.PROPOSALS.FILTERS.ALL_OWNERS') },
  ...agents.value.map(agent => ({ value: agent.id, label: agent.name })),
]);

const hasMore = computed(
  () => proposals.value.length < meta.value.count && !isLoading.value
);

const params = page => ({
  q: searchText.value.trim() || undefined,
  ...Object.fromEntries(
    Object.entries(filters.value).filter(([, value]) => value !== '')
  ),
  page,
});

const load = async (page = 1) => {
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.getProposals(params(page));
    proposals.value =
      page === 1 ? data.payload : [...proposals.value, ...data.payload];
    meta.value = data.meta;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoading.value = false;
  }
};

let searchTimer = null;
watch(searchText, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => load(1), 300);
});
watch(filters, () => load(1), { deep: true });

const openProposal = (id, extra = {}) =>
  router.push({ query: { ...route.query, ...extra, proposta: id } });

const closeEditor = () => {
  const query = { ...route.query };
  ['proposta', 'contato', 'negocio', 'tipo', 'produto'].forEach(
    key => delete query[key]
  );
  router.push({ query });
  load(1);
};

const contactLine = proposal =>
  [proposal.customer_company, proposal.contact?.name]
    .filter((value, index, list) => value && list.indexOf(value) === index)
    .join(' · ');

onMounted(() => {
  if (canSeeOthers.value && !agents.value.length) store.dispatch('agents/get');
  if (!openId.value) load(1);
});

watch(openId, (now, before) => {
  if (!now && before) load(1);
});
</script>

<template>
  <ProposalEditor
    v-if="openId"
    :key="openId"
    :proposal-id="openId"
    :access="access"
    :pipelines="pipelines"
    :initial="{
      contactId: Number(route.query.contato) || null,
      opportunityId: Number(route.query.negocio) || null,
      kind: route.query.tipo || 'sale',
      productId: Number(route.query.produto) || null,
    }"
    @close="closeEditor"
    @created="id => router.replace({ query: { proposta: id } })"
  />
  <div v-else class="flex flex-col gap-4">
    <div class="flex flex-wrap items-center gap-2">
      <Input
        v-model="searchText"
        type="search"
        :placeholder="t('OUTSIDER_CRM.PROPOSALS.FILTERS.SEARCH')"
        :custom-input-class="['h-9 ltr:!pl-8 rtl:!pr-8 !py-1']"
        class="flex-1 min-w-[14rem] max-w-xl"
      >
        <template #prefix>
          <Icon
            icon="i-lucide-search"
            class="absolute -translate-y-1/2 text-n-slate-11 size-4 top-1/2 ltr:left-2 rtl:right-2"
          />
        </template>
      </Input>
      <Button
        size="sm"
        variant="faded"
        color="slate"
        icon="i-lucide-sliders-horizontal"
        :label="
          moreFiltersCount
            ? t('OUTSIDER_CRM.PROPOSALS.FILTERS.MORE_COUNT', {
                count: moreFiltersCount,
              })
            : t('OUTSIDER_CRM.PROPOSALS.FILTERS.MORE')
        "
        @click="showMoreFilters = !showMoreFilters"
      />
      <Spinner v-if="isLoading" :size="16" class="text-n-slate-10" />
      <div class="flex-1" />
      <Button
        icon="i-lucide-plus"
        :label="t('OUTSIDER_CRM.PROPOSALS.NEW')"
        @click="openProposal('nova')"
      />
    </div>

    <div class="flex flex-wrap gap-1.5" role="radiogroup">
      <button
        v-for="option in statusOptions"
        :key="option.value"
        type="button"
        role="radio"
        :aria-checked="filters.status === option.value"
        class="px-3 py-1.5 text-sm rounded-full outline outline-1 -outline-offset-1 transition-colors"
        :class="
          filters.status === option.value
            ? 'bg-n-brand text-white outline-n-brand font-medium'
            : 'outline-n-weak text-n-slate-11 hover:text-n-slate-12 hover:outline-n-slate-6'
        "
        @click="filters.status = option.value"
      >
        {{ option.label }}
      </button>
    </div>

    <div
      v-if="showMoreFilters"
      class="flex flex-wrap items-center gap-2 p-3 rounded-xl bg-n-alpha-1"
    >
      <Select v-model="filters.kind" :options="kindOptions" />
      <Select
        v-if="canSeeOthers"
        v-model="filters.owner_id"
        :options="ownerOptions"
      />
      <label class="flex items-center gap-1 text-xs text-n-slate-11">
        {{ t('OUTSIDER_CRM.PROPOSALS.FILTERS.FROM') }}
        <input
          v-model="filters.from"
          type="date"
          class="!mb-0 !h-8 !py-1 !text-sm rounded-lg !w-36"
        />
      </label>
      <label class="flex items-center gap-1 text-xs text-n-slate-11">
        {{ t('OUTSIDER_CRM.PROPOSALS.FILTERS.TO') }}
        <input
          v-model="filters.to"
          type="date"
          class="!mb-0 !h-8 !py-1 !text-sm rounded-lg !w-36"
        />
      </label>
    </div>

    <p class="mb-0 text-sm text-n-slate-11">
      {{
        t(
          'OUTSIDER_CRM.PROPOSALS.SUMMARY',
          { count: meta.count, total: formatMoney(meta.total_cents) },
          meta.count
        )
      }}
    </p>

    <div
      class="overflow-x-auto outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
    >
      <table class="w-full text-sm min-w-[44rem]">
        <thead>
          <tr class="text-xs text-left border-b text-n-slate-11 border-n-weak">
            <th class="px-4 py-3 font-medium">
              {{ t('OUTSIDER_CRM.PROPOSALS.TABLE.NUMBER') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('OUTSIDER_CRM.PROPOSALS.TABLE.CUSTOMER') }}
            </th>
            <th class="px-4 py-3 font-medium text-right">
              {{ t('OUTSIDER_CRM.PROPOSALS.TABLE.TOTAL') }}
            </th>
            <th class="px-4 py-3 font-medium">
              {{ t('OUTSIDER_CRM.PROPOSALS.TABLE.STATUS') }}
            </th>
            <th v-if="canSeeOthers" class="px-4 py-3 font-medium">
              {{ t('OUTSIDER_CRM.PROPOSALS.TABLE.OWNER') }}
            </th>
            <th class="w-10 px-2 py-3" />
          </tr>
        </thead>
        <tbody>
          <tr v-if="!proposals.length && !isLoading">
            <td
              :colspan="canSeeOthers ? 6 : 5"
              class="px-4 py-10 text-center text-n-slate-11"
            >
              {{ t('OUTSIDER_CRM.PROPOSALS.EMPTY') }}
            </td>
          </tr>
          <tr
            v-for="proposal in proposals"
            :key="proposal.id"
            class="border-b cursor-pointer border-n-weak last:border-0 hover:bg-n-alpha-1"
            @click="openProposal(proposal.id)"
          >
            <td class="px-4 py-3 whitespace-nowrap">
              <span class="font-medium text-n-slate-12">
                {{ proposal.number }}
              </span>
              <span class="block text-xs text-n-slate-11">
                {{
                  t(
                    `OUTSIDER_CRM.PROPOSALS.KIND.${proposal.kind.toUpperCase()}`
                  )
                }}
              </span>
            </td>
            <td class="px-4 py-3">
              <span class="block truncate max-w-[22rem] text-n-slate-12">
                {{ contactLine(proposal) }}
              </span>
              <span class="block truncate max-w-[22rem] text-xs text-n-slate-11">
                {{ proposal.title }}
              </span>
            </td>
            <td class="px-4 py-3 text-right whitespace-nowrap text-n-slate-12">
              {{ formatMoney(proposal.total_cents) }}
            </td>
            <td class="px-4 py-3 whitespace-nowrap">
              <span
                class="px-2 py-0.5 text-xs rounded-md"
                :class="PROPOSAL_STATUS_COLORS[proposal.display_status]"
              >
                {{
                  t(
                    `OUTSIDER_CRM.PROPOSALS.STATUS.${proposal.display_status.toUpperCase()}`
                  )
                }}
              </span>
              <span
                v-if="proposal.valid_until"
                class="block mt-1 text-xs text-n-slate-10"
              >
                {{
                  t('OUTSIDER_CRM.PROPOSALS.VALID_UNTIL_SHORT', {
                    date: formatDate(proposal.valid_until),
                  })
                }}
              </span>
            </td>
            <td v-if="canSeeOthers" class="px-4 py-3 text-n-slate-11">
              {{ proposal.owner?.name || '—' }}
            </td>
            <td class="px-2 py-3">
              <Button
                v-tooltip.top="t('OUTSIDER_CRM.PROPOSALS.PDF.VIEW')"
                size="xs"
                variant="ghost"
                color="slate"
                icon="i-lucide-file-search"
                @click.stop="pdfRef?.open(proposal)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-if="hasMore" class="flex justify-center">
      <Button
        size="sm"
        variant="faded"
        color="slate"
        :label="t('OUTSIDER_CRM.PROPOSALS.LOAD_MORE')"
        @click="load(meta.page + 1)"
      />
    </div>
    <ProposalPdfDialog ref="pdfRef" />
  </div>
</template>
