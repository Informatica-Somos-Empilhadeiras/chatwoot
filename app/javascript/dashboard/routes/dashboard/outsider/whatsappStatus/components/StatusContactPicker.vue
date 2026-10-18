<script setup>
// OUTSIDER: escolher quem vê o status: busca por nome ou número, filtro por região,
// estado e DDD, e marcar um a um ou todos os achados de uma vez.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import WhatsappStatusAPI from 'dashboard/api/outsider/whatsappStatus';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { FOREIGN, buildAreaTree, stateOfArea } from '../areas';
import { errorMessage, formatPhone } from '../helpers';

const props = defineProps({
  inboxId: { type: Number, required: true },
  // { count, areas: { '62': 10, foreign: 1, unknown: 2 } }
  summary: { type: Object, default: null },
});

const emit = defineEmits(['confirm']);

const { t } = useI18n();

const dialogRef = ref(null);
const selected = ref(new Set());
const query = ref('');
// o filtro escolhido na lateral: { key, areas } (areas vazio = todos)
const filter = ref({ key: 'all', areas: [] });
const expanded = ref(new Set());
const contacts = ref([]);
const total = ref(0);
const page = ref(1);
const filteredIds = ref([]);
const isLoading = ref(false);
const isLoadingMore = ref(false);
let requestId = 0;

const tree = computed(() => buildAreaTree(props.summary?.areas || {}));

const allFilteredSelected = computed(
  () =>
    filteredIds.value.length > 0 &&
    filteredIds.value.every(id => selected.value.has(id))
);

const hasMore = computed(() => contacts.value.length < total.value);

const params = () => ({ q: query.value.trim(), areas: filter.value.areas });

const load = async () => {
  requestId += 1;
  const current = requestId;
  isLoading.value = true;
  try {
    const [list, ids] = await Promise.all([
      WhatsappStatusAPI.getAudienceContacts(props.inboxId, {
        ...params(),
        page: 1,
      }),
      WhatsappStatusAPI.getAudienceContacts(props.inboxId, {
        ...params(),
        all_ids: 1,
      }),
    ]);
    if (current !== requestId) return;
    contacts.value = list.data.contacts;
    total.value = list.data.total;
    page.value = 1;
    filteredIds.value = ids.data.ids;
  } catch (error) {
    if (current === requestId) useAlert(errorMessage(t, error));
  } finally {
    if (current === requestId) isLoading.value = false;
  }
};

const loadMore = async () => {
  if (isLoadingMore.value || !hasMore.value) return;
  const current = requestId;
  isLoadingMore.value = true;
  try {
    const { data } = await WhatsappStatusAPI.getAudienceContacts(
      props.inboxId,
      { ...params(), page: page.value + 1 }
    );
    if (current !== requestId) return;
    contacts.value = [...contacts.value, ...data.contacts];
    page.value = data.page;
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isLoadingMore.value = false;
  }
};

const debouncedLoad = useDebounceFn(load, 300);

watch(query, debouncedLoad);

const choose = (key, areas) => {
  filter.value = { key, areas };
  load();
};

const toggleExpanded = key => {
  const next = new Set(expanded.value);
  if (next.has(key)) next.delete(key);
  else next.add(key);
  expanded.value = next;
};

const chevron = key =>
  expanded.value.has(key)
    ? 'i-lucide-chevron-down'
    : 'i-lucide-chevron-right rtl:rotate-180';

const chooseRegion = region => {
  if (!expanded.value.has(region.key)) toggleExpanded(region.key);
  choose(region.key, region.areas);
};

const chooseState = state => {
  if (state.ddds.length > 1 && !expanded.value.has(state.key)) {
    toggleExpanded(state.key);
  }
  choose(state.key, state.areas);
};

const toggle = id => {
  const next = new Set(selected.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  selected.value = next;
};

const toggleAllFiltered = () => {
  const next = new Set(selected.value);
  if (allFilteredSelected.value) filteredIds.value.forEach(id => next.delete(id));
  else filteredIds.value.forEach(id => next.add(id));
  selected.value = next;
};

const clearSelection = () => {
  selected.value = new Set();
};

const areaTag = area => {
  if (area === FOREIGN) return t('OUTSIDER_WHATSAPP_STATUS.PICKER.FOREIGN_TAG');
  const uf = stateOfArea(area);
  return uf ? `${area} · ${uf}` : '';
};

const navClass = key => [
  'flex items-center w-full gap-2 px-2 py-1.5 text-sm rounded-lg text-start',
  filter.value.key === key
    ? 'bg-n-alpha-2 text-n-blue-11 font-medium'
    : 'text-n-slate-12 hover:bg-n-alpha-1',
];

const open = ids => {
  selected.value = new Set(ids);
  query.value = '';
  filter.value = { key: 'all', areas: [] };
  expanded.value = new Set();
  contacts.value = [];
  total.value = 0;
  filteredIds.value = [];
  dialogRef.value.open();
  load();
};

const confirm = () => {
  emit('confirm', [...selected.value]);
  dialogRef.value.close();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('OUTSIDER_WHATSAPP_STATUS.PICKER.TITLE')"
    width="3xl"
    overflow-y-auto
    :confirm-button-label="
      t('OUTSIDER_WHATSAPP_STATUS.PICKER.CONFIRM', { count: selected.size })
    "
    :disable-confirm-button="!selected.size"
    @confirm="confirm"
  >
    <div class="flex flex-col gap-4">
      <!-- Enter na busca não confirma a escolha -->
      <div @keydown.enter.prevent>
        <Input
          v-model="query"
          :placeholder="t('OUTSIDER_WHATSAPP_STATUS.PICKER.SEARCH')"
          autofocus
        />
      </div>
      <div class="flex flex-col gap-4 md:flex-row">
        <nav
          class="flex flex-col flex-shrink-0 gap-0.5 md:w-60 max-h-48 md:max-h-[26rem] overflow-y-auto"
        >
          <button
            type="button"
            :class="navClass('all')"
            @click="choose('all', [])"
          >
            <Icon icon="i-lucide-users" class="flex-shrink-0 size-4" />
            <span class="flex-1 truncate">
              {{ t('OUTSIDER_WHATSAPP_STATUS.PICKER.ALL') }}
            </span>
            <span class="text-xs tabular-nums text-n-slate-10">
              {{ summary?.count ?? '' }}
            </span>
          </button>
          <template v-for="region in tree.regions" :key="region.key">
            <div class="flex items-center">
              <Button
                type="button"
                size="xs"
                variant="ghost"
                color="slate"
                :title="t('OUTSIDER_WHATSAPP_STATUS.PICKER.EXPAND')"
                :icon="chevron(region.key)"
                class="flex-shrink-0"
                @click="toggleExpanded(region.key)"
              />
              <button
                type="button"
                :class="navClass(region.key)"
                @click="chooseRegion(region)"
              >
                <span class="flex-1 truncate">
                  {{ t(`OUTSIDER_WHATSAPP_STATUS.PICKER.REGIONS.${region.key}`) }}
                </span>
                <span class="text-xs tabular-nums text-n-slate-10">
                  {{ region.count }}
                </span>
              </button>
            </div>
            <template v-if="expanded.has(region.key)">
              <template v-for="state in region.states" :key="state.key">
                <div class="flex items-center ltr:pl-6 rtl:pr-6">
                  <Button
                    v-if="state.ddds.length > 1"
                    type="button"
                    size="xs"
                    variant="ghost"
                    color="slate"
                    :title="t('OUTSIDER_WHATSAPP_STATUS.PICKER.EXPAND')"
                    :icon="chevron(state.key)"
                    class="flex-shrink-0"
                    @click="toggleExpanded(state.key)"
                  />
                  <span v-else class="flex-shrink-0 size-6" />
                  <button
                    type="button"
                    :class="navClass(state.key)"
                    @click="chooseState(state)"
                  >
                    <span class="flex-1 truncate">{{ state.name }}</span>
                    <span class="text-xs tabular-nums text-n-slate-10">
                      {{ state.count }}
                    </span>
                  </button>
                </div>
                <template
                  v-if="state.ddds.length > 1 && expanded.has(state.key)"
                >
                  <button
                    v-for="item in state.ddds"
                    :key="item.key"
                    type="button"
                    class="ltr:ml-12 rtl:mr-12 !w-auto"
                    :class="navClass(`ddd-${item.key}`)"
                    @click="choose(`ddd-${item.key}`, item.areas)"
                  >
                    <span class="flex-1 truncate">
                      {{
                        t('OUTSIDER_WHATSAPP_STATUS.PICKER.DDD', {
                          ddd: item.ddd,
                          city: item.city,
                        })
                      }}
                    </span>
                    <span class="text-xs tabular-nums text-n-slate-10">
                      {{ item.count }}
                    </span>
                  </button>
                </template>
              </template>
            </template>
          </template>
          <button
            v-if="tree.others.count"
            type="button"
            :class="navClass('others')"
            @click="choose('others', tree.others.areas)"
          >
            <Icon icon="i-lucide-globe" class="flex-shrink-0 size-4" />
            <span class="flex-1 truncate">
              {{ t('OUTSIDER_WHATSAPP_STATUS.PICKER.OTHERS') }}
            </span>
            <span class="text-xs tabular-nums text-n-slate-10">
              {{ tree.others.count }}
            </span>
          </button>
          <button
            v-if="tree.unknown.count"
            type="button"
            :class="navClass('unknown')"
            @click="choose('unknown', tree.unknown.areas)"
          >
            <Icon icon="i-lucide-circle-help" class="flex-shrink-0 size-4" />
            <span class="flex-1 truncate">
              {{ t('OUTSIDER_WHATSAPP_STATUS.PICKER.UNKNOWN') }}
            </span>
            <span class="text-xs tabular-nums text-n-slate-10">
              {{ tree.unknown.count }}
            </span>
          </button>
        </nav>

        <div class="flex flex-col flex-1 min-w-0 gap-2">
          <div
            class="flex flex-wrap items-center gap-2 px-3 py-2 rounded-lg min-h-11 bg-n-alpha-1"
          >
            <Checkbox
              :model-value="allFilteredSelected"
              :indeterminate="
                !allFilteredSelected &&
                filteredIds.some(id => selected.has(id))
              "
              :disabled="!filteredIds.length"
              @update:model-value="toggleAllFiltered"
            />
            <button
              type="button"
              class="flex-1 text-sm text-start text-n-slate-12 disabled:text-n-slate-10"
              :disabled="!filteredIds.length"
              @click="toggleAllFiltered"
            >
              {{
                allFilteredSelected
                  ? t('OUTSIDER_WHATSAPP_STATUS.PICKER.UNSELECT_FOUND', {
                      count: filteredIds.length,
                    })
                  : t('OUTSIDER_WHATSAPP_STATUS.PICKER.SELECT_FOUND', {
                      count: filteredIds.length,
                    })
              }}
            </button>
            <Button
              v-if="selected.size"
              size="xs"
              variant="ghost"
              color="slate"
              :label="t('OUTSIDER_WHATSAPP_STATUS.PICKER.CLEAR')"
              @click="clearSelection"
            />
          </div>

          <div
            class="flex flex-col overflow-y-auto h-72 md:h-[23rem] rounded-lg outline outline-1 -outline-offset-1 outline-n-weak"
          >
            <div v-if="isLoading" class="flex justify-center p-6">
              <Spinner class="text-n-slate-10" />
            </div>
            <p
              v-else-if="!contacts.length"
              class="p-6 mb-0 text-sm text-center text-n-slate-11"
            >
              {{ t('OUTSIDER_WHATSAPP_STATUS.PICKER.EMPTY') }}
            </p>
            <template v-else>
              <label
                v-for="contact in contacts"
                :key="contact.id"
                class="flex items-center gap-3 px-3 py-2 cursor-pointer hover:bg-n-alpha-1"
              >
                <Checkbox
                  :model-value="selected.has(contact.id)"
                  @update:model-value="toggle(contact.id)"
                />
                <Avatar
                  :name="contact.name || contact.phone || ''"
                  :src="contact.avatar_url"
                  :size="32"
                  rounded-full
                />
                <span class="flex flex-col flex-1 min-w-0">
                  <span
                    class="text-sm truncate"
                    :class="contact.name ? 'text-n-slate-12' : 'text-n-slate-10'"
                  >
                    {{
                      contact.name ||
                      t('OUTSIDER_WHATSAPP_STATUS.PICKER.NO_NAME')
                    }}
                  </span>
                  <span
                    v-if="contact.phone"
                    class="text-xs truncate text-n-slate-11"
                  >
                    {{ formatPhone(contact.phone) }}
                  </span>
                </span>
                <span
                  v-if="areaTag(contact.area)"
                  class="flex-shrink-0 px-2 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
                >
                  {{ areaTag(contact.area) }}
                </span>
              </label>
              <div v-if="hasMore" class="flex justify-center p-2">
                <Button
                  size="sm"
                  variant="ghost"
                  color="slate"
                  :is-loading="isLoadingMore"
                  :label="
                    t('OUTSIDER_WHATSAPP_STATUS.PICKER.MORE', {
                      count: total - contacts.length,
                    })
                  "
                  @click="loadMore"
                />
              </div>
            </template>
          </div>
          <p class="mb-0 text-xs text-n-slate-10">
            {{
              t('OUTSIDER_WHATSAPP_STATUS.PICKER.SELECTED', {
                count: selected.size,
              })
            }}
          </p>
        </div>
      </div>
    </div>
  </Dialog>
</template>
