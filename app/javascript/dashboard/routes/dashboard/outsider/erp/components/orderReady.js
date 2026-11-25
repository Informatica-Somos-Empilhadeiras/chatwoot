// OUTSIDER: Emitir relatório e Enviar da OS só ficam ativos com a OS concluída e o checklist já respondido (sincronizado
// do app do técnico para o ERP). Confere o checklist no servidor só quando a OS está concluída e o botão está à vista.
import { ref, computed, watch } from 'vue';
import ErpAPI from 'dashboard/api/outsider/erp';

// source: () => ({ company, code, concluded }); visible: () => boolean
export const useOrderReady = (source, visible = () => true) => {
  const answered = ref(null);
  const checking = ref(false);
  let token = 0;

  const check = async () => {
    const { company, code, concluded } = source();
    token += 1;
    const mine = token;
    answered.value = null;
    if (!concluded || !company || !code) return;
    checking.value = true;
    try {
      const { data } = await ErpAPI.orderChecklist(company, code);
      if (mine === token) answered.value = data.answered === true;
    } catch {
      if (mine === token) answered.value = false;
    } finally {
      if (mine === token) checking.value = false;
    }
  };

  watch(
    () => {
      const { company, code, concluded } = source();
      return [company, code, concluded, visible()];
    },
    ([, , , show]) => {
      if (show) check();
    },
    { immediate: true }
  );

  const ready = computed(
    () => source().concluded === true && answered.value === true
  );
  return { ready, checking, check };
};
