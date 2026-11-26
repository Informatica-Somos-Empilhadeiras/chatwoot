<script setup>
// OUTSIDER (Maps): lateral esquerda do Mapa dos agendamentos: o cadastro do cliente no Mais Prático, com os campos vazios
// completados pela consulta do CNPJ (marca "API"; "Gravar no Mais Prático" grava só esses vazios, ver
// Outsider::Erp::ClientCompleter) e os contatos: os do chat ligados ao cliente e os do cadastro do ERP.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import MapsAPI from 'dashboard/api/outsider/maps';

const props = defineProps({
  info: { type: Object, required: true },
});
const emit = defineEmits(['saved']);

const { t } = useI18n();
const route = useRoute();
const isSaving = ref(false);

const FIELDS = [
  ['documento', 'DOCUMENT'],
  ['fantasia', 'TRADE_NAME'],
  ['ie', 'IE'],
  ['endereco', 'STREET'],
  ['numero', 'NUMBER'],
  ['complemento', 'COMPLEMENT'],
  ['bairro', 'DISTRICT'],
  ['cidade', 'CITY'],
  ['uf', 'STATE'],
  ['cep', 'ZIP'],
  ['fone', 'PHONE'],
  ['celular', 'MOBILE'],
  ['email', 'EMAIL'],
];

const record = computed(() => props.info.record || {});
const completed = computed(() => props.info.completed || {});
const rows = computed(() =>
  FIELDS.map(([key, label]) => ({
    key,
    label: t(`OUTSIDER_MAPS.MAP.FIELDS.${label}`),
    value: record.value[key] || completed.value[key] || '',
    fromApi: !record.value[key] && !!completed.value[key],
  })).filter(row => row.value)
);
const hasCompleted = computed(() => Object.keys(completed.value).length > 0);
const missing = computed(() =>
  FIELDS.filter(
    ([key]) => key !== 'celular' && !record.value[key] && !completed.value[key]
  ).map(([, label]) => t(`OUTSIDER_MAPS.MAP.FIELDS.${label}`))
);

const conversationLink = id =>
  `/app/accounts/${route.params.accountId}/conversations/${id}`;
const contactLink = id =>
  `/app/accounts/${route.params.accountId}/contacts/${id}`;

const save = async () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('OUTSIDER_MAPS.MAP.COMPLETE_CONFIRM'))) return;
  isSaving.value = true;
  try {
    const { data } = await MapsAPI.completeClient(
      props.info.company,
      props.info.code,
      completed.value
    );
    useAlert(
      data.written.length
        ? t('OUTSIDER_MAPS.MAP.COMPLETE_DONE', { count: data.written.length })
        : t('OUTSIDER_MAPS.MAP.COMPLETE_NOTHING')
    );
    emit('saved');
  } catch {
    useAlert(t('OUTSIDER_MAPS.MAP.COMPLETE_FAILED'));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-3" data-map-client-sheet>
    <div>
      <h3 class="mb-0 text-base font-semibold text-n-slate-12">
        {{ record.nome || info.name }}
      </h3>
      <p class="mb-0 text-xs text-n-slate-11">
        {{
          t('OUTSIDER_MAPS.MAP.CLIENT_CODE', {
            code: info.code,
            unit: info.unit,
          })
        }}
      </p>
    </div>

    <section class="flex flex-col">
      <span
        class="mb-1 text-[11px] font-semibold tracking-wide uppercase text-n-slate-10"
      >
        {{ t('OUTSIDER_MAPS.MAP.CLIENT_DATA') }}
      </span>
      <div
        v-for="row in rows"
        :key="row.key"
        class="flex justify-between gap-3 py-1 text-[13px] border-b border-dashed border-n-weak"
      >
        <span class="text-n-slate-11 shrink-0">{{ row.label }}</span>
        <span class="text-right break-words min-w-0 text-n-slate-12">
          {{ row.value }}
          <span
            v-if="row.fromApi"
            class="ml-1 px-1 rounded text-[10px] font-bold bg-n-teal-3 text-n-teal-11"
            >{{ t('OUTSIDER_MAPS.MAP.API') }}</span
          >
        </span>
      </div>
      <p v-if="hasCompleted" class="mt-2 mb-0 text-[11px] text-n-slate-10">
        {{ t('OUTSIDER_MAPS.MAP.API_HINT') }}
      </p>
      <p v-if="missing.length" class="mt-1 mb-0 text-[11px] text-n-amber-11">
        {{ t('OUTSIDER_MAPS.MAP.MISSING', { fields: missing.join(', ') }) }}
      </p>
      <button
        v-if="hasCompleted && info.can_complete"
        type="button"
        class="mt-2 oa-btn !h-8 !text-xs self-start"
        :disabled="isSaving"
        data-map-complete
        @click="save"
      >
        <Icon icon="i-lucide-database" class="size-3.5" />
        {{ t('OUTSIDER_MAPS.MAP.COMPLETE') }}
      </button>
    </section>

    <section class="flex flex-col gap-1.5">
      <span
        class="text-[11px] font-semibold tracking-wide uppercase text-n-slate-10"
      >
        {{ t('OUTSIDER_MAPS.MAP.CONTACTS') }}
      </span>
      <p
        v-if="!info.contacts?.length && !info.erp_contacts?.length"
        class="mb-0 text-xs text-n-slate-10"
      >
        {{ t('OUTSIDER_MAPS.MAP.NO_CONTACTS') }}
      </p>
      <div
        v-for="person in info.contacts || []"
        :key="`c${person.id}`"
        class="p-2 border rounded-lg border-n-weak"
      >
        <b class="text-sm text-n-slate-12">{{ person.name }}</b>
        <p class="mb-1 text-xs text-n-slate-11">
          {{ [person.phone, person.email].filter(Boolean).join(' · ') }}
        </p>
        <div class="flex gap-1.5">
          <a
            v-if="person.conversation_id"
            :href="conversationLink(person.conversation_id)"
            class="oa-ghost !h-7 !text-xs"
          >
            <Icon icon="i-lucide-message-circle" class="size-3.5" />
            {{ t('OUTSIDER_MAPS.MAP.OPEN_CHAT') }}
          </a>
          <a :href="contactLink(person.id)" class="oa-ghost !h-7 !text-xs">
            {{ t('OUTSIDER_MAPS.MAP.OPEN_CONTACT') }}
          </a>
        </div>
      </div>
      <div
        v-for="(person, index) in info.erp_contacts || []"
        :key="`e${index}`"
        class="p-2 border rounded-lg border-n-weak"
      >
        <b class="text-sm text-n-slate-12">{{ person.nome || '—' }}</b>
        <span class="ml-1 text-xs text-n-slate-10">
          {{ person.cargo || t('OUTSIDER_MAPS.MAP.FROM_ERP') }}
        </span>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ [person.fone, person.email].filter(Boolean).join(' · ') }}
        </p>
      </div>
    </section>
  </div>
</template>
