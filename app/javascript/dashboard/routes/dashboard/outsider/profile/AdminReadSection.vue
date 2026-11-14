<script setup>
// OUTSIDER: opção do Perfil (só administradores) para abrir conversas de outros
// agentes, ou sem agente, sem marcá-las como lidas. Regra no servidor:
// app/services/outsider/leitura_admin.rb. Ligado = preserva (padrão).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useUISettings } from 'dashboard/composables/useUISettings';
import SectionLayout from 'dashboard/routes/dashboard/settings/account/components/SectionLayout.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const SETTING = 'outsider_marcar_lida_outros';

const { t } = useI18n();
const { isAdmin } = useAdmin();
const { uiSettings, updateUISettings } = useUISettings();

const saving = ref(false);
const preserva = computed(() => !uiSettings.value?.[SETTING]);

const toggle = async () => {
  if (saving.value) return;
  saving.value = true;
  const next = !preserva.value;
  try {
    await updateUISettings({ [SETTING]: !next });
    useAlert(t(next ? 'OUTSIDER_LEITURA.ON' : 'OUTSIDER_LEITURA.OFF'));
  } catch (error) {
    useAlert(t('OUTSIDER_LEITURA.ERROR'));
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <SectionLayout
    v-if="isAdmin"
    with-border
    :title="t('OUTSIDER_LEITURA.TITLE')"
    :description="t('OUTSIDER_LEITURA.NOTE')"
  >
    <div
      class="flex items-start justify-between gap-4 p-4 border rounded-xl border-n-weak bg-n-solid-1"
      data-outsider-leitura
    >
      <div class="flex flex-col gap-1 min-w-0">
        <p class="text-sm font-medium text-n-slate-12">
          {{ t('OUTSIDER_LEITURA.LABEL') }}
        </p>
        <p class="text-sm text-n-slate-11">
          {{
            preserva
              ? t('OUTSIDER_LEITURA.ON_HINT')
              : t('OUTSIDER_LEITURA.OFF_HINT')
          }}
        </p>
      </div>
      <Switch
        :model-value="preserva"
        :aria-label="t('OUTSIDER_LEITURA.LABEL')"
        class="mt-1"
        @change="toggle"
      />
    </div>
  </SectionLayout>
</template>
