// OUTSIDER: um relógio só para todos os cards da lista (a hora "Ontem"/"13:59" muda à meia-noite).
import { ref } from 'vue';

const now = ref(Date.now());
let timer = null;

export const useMinuteClock = () => {
  if (!timer) {
    timer = setInterval(() => {
      now.value = Date.now();
    }, 60000);
  }
  return now;
};
