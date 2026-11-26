<script setup>
// OUTSIDER: "Locais do cliente" no painel do contato da conversa (Google Maps na agenda). Só a lista compacta, sem mapa
// (o mapa fica no Agendar OS, no evento e no Mapa dos agendamentos): nome, endereço, Maps, Waze, enviar no chat,
// principal e apagar. Adicionar usa a janela de localização
// (busca, link do Google Maps, coordenadas, pin no mapa); o local que o cliente manda no WhatsApp tem "Salvar no
// cliente" na própria bolha (LocationCard.vue), que avisa este bloco por PLACES_CHANGED_EVENT.
import { onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import SendLocationDialog from 'dashboard/components/widgets/WootWriter/outsider/SendLocationDialog.vue';
import MapsAPI from 'dashboard/api/outsider/maps';
import LocationsAPI from 'dashboard/api/outsider/locations';
import { PLACES_CHANGED_EVENT } from 'dashboard/helper/outsider/maps';
import {
  formatCoordinates,
  googleMapsUrl,
  wazeUrl,
} from 'dashboard/helper/outsider/location';

const props = defineProps({
  contactId: { type: Number, default: null },
  conversationId: { type: [Number, String], default: null },
});

const { t } = useI18n();
const store = useStore();

const places = ref([]);
const isLoading = ref(false);
const busyId = ref(null);
const pickRef = ref(null);

const errorText = error => {
  const code = error?.response?.data?.error;
  const key = `OUTSIDER_MAPS.ERRORS.${String(code || '').toUpperCase()}`;
  return code && t(key) !== key ? t(key) : t('OUTSIDER_MAPS.ERRORS.DEFAULT');
};

const load = async () => {
  if (!props.contactId) return;
  isLoading.value = true;
  try {
    const { data } = await MapsAPI.places(props.contactId);
    places.value = data.payload || [];
  } catch {
    places.value = [];
  } finally {
    isLoading.value = false;
  }
};

const onChanged = contactId => {
  if (Number(contactId) === Number(props.contactId)) load();
};

onMounted(() => {
  load();
  emitter.on(PLACES_CHANGED_EVENT, onChanged);
});
onBeforeUnmount(() => emitter.off(PLACES_CHANGED_EVENT, onChanged));
watch(() => props.contactId, load);

const add = async place => {
  try {
    await MapsAPI.createPlace(props.contactId, place);
    await load();
    useAlert(t('OUTSIDER_MAPS.PLACES.ADDED'));
  } catch (error) {
    useAlert(errorText(error));
  }
};

const makeMain = async item => {
  busyId.value = item.id;
  try {
    await MapsAPI.updatePlace(props.contactId, item.id, { main: true });
    await load();
  } catch (error) {
    useAlert(errorText(error));
  } finally {
    busyId.value = null;
  }
};

const remove = async item => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('OUTSIDER_MAPS.PLACES.REMOVE_CONFIRM'))) return;
  busyId.value = item.id;
  try {
    await MapsAPI.removePlace(props.contactId, item.id);
    await load();
  } catch (error) {
    useAlert(errorText(error));
  } finally {
    busyId.value = null;
  }
};

// manda o pin do WhatsApp nesta conversa (só nas caixas da Evolution; a resposta diz quando não dá)
const sendInChat = async item => {
  busyId.value = item.id;
  try {
    const { data } = await LocationsAPI.send(Number(props.conversationId), {
      name: item.name,
      address: item.address || '',
      latitude: item.latitude,
      longitude: item.longitude,
    });
    if (data?.message) store.dispatch('addMessage', data.message);
    useAlert(t('OUTSIDER_WHATSAPP.SEND_LOCATION.SENT'));
  } catch (error) {
    const code = error?.response?.data?.error;
    const key = `OUTSIDER_WHATSAPP.SEND_LOCATION.ERRORS.${String(code || '').toUpperCase()}`;
    useAlert(code && t(key) !== key ? t(key) : errorText(error));
  } finally {
    busyId.value = null;
  }
};

const smallButton =
  'inline-flex items-center gap-1 !px-1.5 !py-0.5 text-[11px] font-medium border rounded-md border-n-weak text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-50';
</script>

<template>
  <section
    v-if="contactId"
    class="flex flex-col gap-2 px-4 py-3 border-b border-n-weak"
    data-contact-places
  >
    <div class="flex items-center justify-between gap-2">
      <span
        class="flex items-center gap-1.5 text-xs font-semibold tracking-wide uppercase text-n-slate-11"
      >
        <Icon icon="i-lucide-map-pin" class="size-3.5" />
        {{ t('OUTSIDER_MAPS.PLACES.TITLE') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 !p-0 text-xs font-semibold text-n-teal-11 hover:underline"
        data-contact-places-add
        @click="pickRef?.open()"
      >
        <Icon icon="i-lucide-plus" class="size-3.5" />
        {{ t('OUTSIDER_MAPS.PLACES.ADD') }}
      </button>
    </div>

    <p v-if="!places.length && !isLoading" class="mb-0 text-xs text-n-slate-10">
      {{ t('OUTSIDER_MAPS.PLACES.EMPTY') }}
    </p>

    <div
      v-for="item in places"
      :key="item.id"
      class="flex flex-col gap-1.5 !px-2.5 !py-2 border rounded-lg border-n-weak"
      data-contact-place
    >
      <div class="flex items-start gap-2">
        <Icon
          icon="i-lucide-star"
          class="mt-0.5 size-3.5 shrink-0"
          :class="item.main ? 'text-n-amber-10' : 'text-n-slate-8'"
        />
        <span class="flex flex-col flex-1 min-w-0">
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ item.name }}
          </span>
          <span class="text-xs line-clamp-2 text-n-slate-11">
            {{ item.address || formatCoordinates(item) }}
          </span>
        </span>
      </div>
      <div class="flex flex-wrap gap-1 pl-5">
        <a
          :href="googleMapsUrl(item)"
          target="_blank"
          rel="noopener noreferrer"
          :class="smallButton"
          data-contact-place-maps
        >
          <Icon icon="i-lucide-map" class="size-3" />
          {{ t('OUTSIDER_MAPS.VIEW.OPEN_MAPS') }}
        </a>
        <a
          :href="wazeUrl(item)"
          target="_blank"
          rel="noopener noreferrer"
          :class="smallButton"
        >
          <Icon icon="i-lucide-navigation" class="size-3" />
          {{ t('OUTSIDER_MAPS.VIEW.WAZE') }}
        </a>
        <button
          v-if="conversationId"
          type="button"
          :class="smallButton"
          :disabled="busyId === item.id"
          data-contact-place-send
          @click="sendInChat(item)"
        >
          <Icon icon="i-lucide-send" class="size-3" />
          {{ t('OUTSIDER_MAPS.PLACES.SEND') }}
        </button>
        <button
          v-if="!item.main"
          type="button"
          :class="smallButton"
          :disabled="busyId === item.id"
          data-contact-place-main
          @click="makeMain(item)"
        >
          <Icon icon="i-lucide-star" class="size-3" />
          {{ t('OUTSIDER_MAPS.PLACES.MAKE_MAIN') }}
        </button>
        <button
          v-tooltip.top="t('OUTSIDER_MAPS.PLACES.REMOVE')"
          type="button"
          :class="smallButton"
          class="hover:!text-n-ruby-11"
          :disabled="busyId === item.id"
          :aria-label="t('OUTSIDER_MAPS.PLACES.REMOVE')"
          data-contact-place-remove
          @click="remove(item)"
        >
          <Icon icon="i-lucide-trash-2" class="size-3" />
        </button>
      </div>
    </div>

    <SendLocationDialog
      ref="pickRef"
      mode="pick"
      :pick-label="t('OUTSIDER_MAPS.PLACES.SAVE')"
      @picked="add"
    />
  </section>
</template>
