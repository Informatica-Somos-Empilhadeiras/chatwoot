<script setup>
// OUTSIDER: convite de um colega para sussurrar na ligação dele (Entrega 26). Entrar liga para a ligação dele
// ouvindo tudo e falando só com ele; o convite some sozinho em 2 minutos.
import { useI18n } from 'vue-i18n';
import Avatar from 'next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useAlert } from 'dashboard/composables';
import { phone, acceptInvite, declineInvite } from './phone';

const { t } = useI18n();

const join = () => {
  const error = acceptInvite();
  if (error) useAlert(t(`OUTSIDER_VOICE.PHONE.ERRORS.${error}`));
};
</script>

<template>
  <Teleport to="body">
    <div
      v-if="phone.invite"
      class="fixed z-[9997] bottom-4 ltr:right-4 rtl:left-4 w-80 max-w-[calc(100vw-2rem)] flex flex-col gap-3 p-4 border shadow-2xl rounded-2xl border-n-weak bg-n-solid-2"
      role="alertdialog"
      :aria-label="t('OUTSIDER_VOICE.INVITE.TITLE')"
      data-testid="outsider-whisper-invite"
    >
      <span
        class="flex items-center gap-1.5 text-xs font-medium text-n-violet-11"
      >
        <Icon icon="i-lucide-ear" class="size-4" />
        {{ t('OUTSIDER_VOICE.INVITE.TITLE') }}
      </span>
      <div class="flex items-center gap-3">
        <Avatar
          :size="40"
          :name="phone.invite.name"
          rounded-full
          class="shrink-0"
        />
        <p class="mb-0 text-sm text-n-slate-12">
          {{
            t('OUTSIDER_VOICE.INVITE.BODY', {
              name: phone.invite.name,
              customer: phone.invite.customer,
            })
          }}
        </p>
      </div>
      <div class="grid grid-cols-2 gap-2">
        <Button
          slate
          faded
          :label="t('OUTSIDER_VOICE.INVITE.DECLINE')"
          @click="declineInvite"
        />
        <Button
          teal
          icon="i-lucide-phone"
          :label="t('OUTSIDER_VOICE.INVITE.JOIN')"
          data-testid="outsider-whisper-join"
          @click="join"
        />
      </div>
    </div>
  </Teleport>
</template>
