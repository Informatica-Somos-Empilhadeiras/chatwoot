<script setup>
// OUTSIDER: janela "você recebeu um negócio encaminhado". Aparece no meio da tela, em qualquer
// página do Chatwoot, e só fecha pelos botões (clicar fora ou Esc não fecha). Fechar marca o aviso
// como visto; a bolinha vermelha no menu do CRM continua até a pessoa abrir o negócio. Negócio que
// chegou sem responsável tem "Pegar para mim": quem pegar primeiro fica com ele.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { claimOpportunity, crmState, markReceived } from '../crmStore';
import { formatMoney } from '../helpers';

const { t } = useI18n();
const router = useRouter();

const pending = computed(() =>
  crmState.received.filter(item => !item.notified)
);

const origin = item => {
  if (item.rule) {
    return t('OUTSIDER_CRM.NOTICE.BY_RULE', {
      unit: item.from_unit,
      rule: item.rule,
    });
  }
  return item.by
    ? t('OUTSIDER_CRM.NOTICE.BY_PERSON', {
        unit: item.from_unit,
        name: item.by,
      })
    : t('OUTSIDER_CRM.NOTICE.FROM_UNIT', { unit: item.from_unit });
};

const dismiss = () =>
  markReceived(
    pending.value.map(item => item.opportunity_id),
    false
  );

// abrir o negócio no CRM (o painel marca como aberto)
const openDeal = item => {
  markReceived([item.opportunity_id], true);
  router.push({
    path: frontendURL(`accounts/${crmState.accountId}/crm/opportunities`),
    query: { negocio: item.opportunity_id },
  });
};

const claimingId = ref(null);

const claim = async item => {
  claimingId.value = item.opportunity_id;
  const data = await claimOpportunity(t, { id: item.opportunity_id });
  claimingId.value = null;
  if (data) openDeal(item);
};

const openConversation = item => {
  markReceived([item.opportunity_id], true);
  router.push(
    frontendURL(
      `accounts/${crmState.accountId}/conversations/${item.conversation_display_id}`
    )
  );
};
</script>

<template>
  <Teleport to="body">
    <div
      v-if="pending.length"
      class="fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-n-alpha-black1 backdrop-blur-[2px]"
      role="alertdialog"
      aria-modal="true"
    >
      <div
        class="flex flex-col w-full max-w-lg max-h-[85vh] overflow-hidden rounded-2xl shadow-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-container"
      >
        <header class="flex items-start gap-3 p-5 pb-3">
          <span
            class="flex items-center justify-center rounded-full size-10 shrink-0 bg-n-amber-3 text-n-amber-11"
          >
            <Icon icon="i-lucide-inbox" class="size-5" />
          </span>
          <div class="flex flex-col gap-0.5">
            <h2 class="mb-0 text-base font-semibold text-n-slate-12">
              {{ t('OUTSIDER_CRM.NOTICE.TITLE', pending.length) }}
            </h2>
            <p class="mb-0 text-sm text-n-slate-11">
              {{ t('OUTSIDER_CRM.NOTICE.SUBTITLE') }}
            </p>
          </div>
        </header>

        <div class="flex flex-col gap-2 px-5 overflow-y-auto">
          <article
            v-for="item in pending"
            :key="item.opportunity_id"
            class="flex flex-col gap-2 p-3 rounded-xl bg-n-alpha-1"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="flex flex-col min-w-0 gap-0.5">
                <span class="text-xs text-n-slate-11">
                  {{ item.code }} · {{ item.to_unit }}
                </span>
                <span class="text-sm font-medium text-n-slate-12">
                  {{ item.title }}
                </span>
                <span class="text-xs text-n-slate-11">
                  {{ item.contact_name }}
                </span>
              </div>
              <span class="text-sm font-semibold shrink-0 text-n-teal-11">
                {{ formatMoney(item.value_cents) }}
              </span>
            </div>
            <span class="text-xs text-n-slate-11">
              {{ origin(item) }}
              <template v-if="item.reason">
                · {{ t('OUTSIDER_CRM.NOTICE.REASON', { reason: item.reason }) }}
              </template>
            </span>
            <p
              v-if="item.notes"
              class="px-2 py-1.5 mb-0 text-xs whitespace-pre-line rounded-lg bg-n-alpha-2 text-n-slate-12"
            >
              {{ item.notes }}
            </p>
            <span v-if="!item.owner_id" class="text-xs text-n-amber-11">
              {{ t('OUTSIDER_CRM.NOTICE.NO_OWNER') }}
            </span>
            <div class="flex flex-wrap gap-2">
              <Button
                v-if="item.can_claim"
                size="sm"
                icon="i-lucide-hand"
                :label="t('OUTSIDER_CRM.CLAIM.BUTTON_ME')"
                :is-loading="claimingId === item.opportunity_id"
                @click="claim(item)"
              />
              <Button
                size="sm"
                :variant="item.can_claim ? 'faded' : 'solid'"
                :color="item.can_claim ? 'slate' : 'blue'"
                icon="i-lucide-handshake"
                :label="t('OUTSIDER_CRM.NOTICE.OPEN_DEAL')"
                @click="openDeal(item)"
              />
              <Button
                v-if="item.conversation_display_id"
                size="sm"
                variant="faded"
                color="slate"
                icon="i-lucide-message-circle"
                :label="t('OUTSIDER_CRM.NOTICE.OPEN_CONVERSATION')"
                @click="openConversation(item)"
              />
            </div>
          </article>
        </div>

        <footer class="flex justify-end gap-2 p-5 pt-4">
          <Button
            variant="faded"
            color="slate"
            :label="t('OUTSIDER_CRM.NOTICE.CLOSE')"
            @click="dismiss"
          />
        </footer>
      </div>
    </div>
  </Teleport>
</template>
