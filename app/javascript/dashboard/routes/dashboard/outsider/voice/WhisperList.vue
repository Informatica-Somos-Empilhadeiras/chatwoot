<script setup>
// OUTSIDER: quem está sussurrando na ligação do atendente (Entrega 26). Só os atendentes ouvem quem sussurra;
// o selo diz se o cliente também está ouvindo. O supervisor abre e fecha sozinho; o colega convidado pede, e o
// atendente permite ou recusa aqui (ou abre e fecha quando quiser). O convidado pode ser tirado da ligação.
import { useI18n } from 'vue-i18n';
import Avatar from 'next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { removeFromConference, setWhisperMode } from './phone';

defineProps({
  whispers: { type: Array, required: true },
});

const { t } = useI18n();
</script>

<template>
  <div class="flex flex-col gap-1.5" data-testid="outsider-whispers">
    <div
      v-for="whisper in whispers"
      :key="whisper.id"
      class="flex flex-col gap-1.5 px-2.5 py-2 rounded-xl"
      :class="
        whisper.state === 'ended'
          ? 'opacity-50 bg-n-alpha-1'
          : 'bg-n-violet-2 outline outline-1 -outline-offset-1 outline-n-violet-5'
      "
    >
      <div class="flex items-center gap-2">
        <Avatar :size="28" :name="whisper.name" rounded-full class="shrink-0" />
        <div class="flex flex-col flex-1 min-w-0">
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ whisper.name }}
          </span>
          <span class="flex items-center gap-1 text-xs text-n-violet-11">
            <Icon
              :icon="
                whisper.mode === 'open' ? 'i-lucide-users' : 'i-lucide-ear'
              "
              class="size-3.5"
            />
            {{
              t(
                `OUTSIDER_VOICE.WHISPER.${whisper.kind === 'supervisor' ? 'SUPERVISOR' : 'GUEST'}`
              )
            }}
            ·
            {{
              whisper.mode === 'open'
                ? t('OUTSIDER_VOICE.WHISPER.CUSTOMER_HEARS')
                : t('OUTSIDER_VOICE.WHISPER.ONLY_AGENTS')
            }}
          </span>
        </div>
        <template v-if="whisper.kind === 'guest' && whisper.state !== 'ended'">
          <Button
            xs
            ghost
            slate
            :icon="
              whisper.mode === 'open' ? 'i-lucide-ear' : 'i-lucide-megaphone'
            "
            :title="
              whisper.mode === 'open'
                ? t('OUTSIDER_VOICE.WHISPER.STOP_CUSTOMER_HEAR')
                : t('OUTSIDER_VOICE.WHISPER.LET_CUSTOMER_HEAR')
            "
            data-testid="outsider-whisper-toggle"
            @click="
              setWhisperMode(
                whisper.id,
                whisper.mode === 'open' ? 'whisper' : 'open'
              )
            "
          />
          <Button
            xs
            ghost
            ruby
            icon="i-lucide-x"
            :title="t('OUTSIDER_VOICE.WHISPER.REMOVE')"
            @click="removeFromConference(whisper.id)"
          />
        </template>
      </div>
      <div
        v-if="whisper.request"
        class="flex flex-wrap items-center justify-between gap-2 px-2 py-1.5 text-xs rounded-lg bg-n-amber-3 text-n-amber-11"
        data-testid="outsider-whisper-request"
      >
        <span>{{
          t('OUTSIDER_VOICE.WHISPER.REQUEST', { name: whisper.name })
        }}</span>
        <span class="flex gap-1">
          <Button
            xs
            slate
            faded
            :label="t('OUTSIDER_VOICE.WHISPER.DENY')"
            @click="setWhisperMode(whisper.id, 'whisper', false)"
          />
          <Button
            xs
            teal
            :label="t('OUTSIDER_VOICE.WHISPER.ALLOW')"
            data-testid="outsider-whisper-allow"
            @click="setWhisperMode(whisper.id, 'open')"
          />
        </span>
      </div>
    </div>
  </div>
</template>
