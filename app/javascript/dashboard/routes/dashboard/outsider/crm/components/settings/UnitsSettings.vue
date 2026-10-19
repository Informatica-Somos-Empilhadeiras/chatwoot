<script setup>
// OUTSIDER: unidades comerciais do grupo e seus membros. Vendedor vê as oportunidades da
// unidade e edita as suas; gestor edita todas e configura os pipelines da unidade.
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/outsider/crm';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SettingsSection from './SettingsSection.vue';
import { errorMessage } from '../../helpers';

const props = defineProps({
  units: { type: Array, required: true },
});

const emit = defineEmits(['changed']);

const { t } = useI18n();
const store = useStore();
const agents = useMapGetter('agents/getAgents');

const selectedId = ref(null);
const unit = ref(null);
const dialogRef = ref(null);
const unitForm = ref({ id: null, name: '', description: '' });
const newMemberId = ref('');
const newMemberRole = ref('seller');
const isSaving = ref(false);

const roleOptions = computed(() => [
  { value: 'seller', label: t('OUTSIDER_CRM.SETTINGS.UNITS.ROLES.SELLER') },
  { value: 'manager', label: t('OUTSIDER_CRM.SETTINGS.UNITS.ROLES.MANAGER') },
]);

const availableAgents = computed(() => {
  const memberIds = (unit.value?.members || []).map(member => member.user_id);
  return agents.value
    .filter(agent => !memberIds.includes(agent.id))
    .map(agent => ({ value: agent.id, label: agent.name }));
});

const selectUnit = async id => {
  selectedId.value = id;
  try {
    const { data } = await CrmAPI.getUnit(id);
    unit.value = data;
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const openUnitDialog = (current = null) => {
  unitForm.value = current
    ? { id: current.id, name: current.name, description: current.description }
    : { id: null, name: '', description: '' };
  dialogRef.value?.open();
};

const saveUnit = async () => {
  if (!unitForm.value.name.trim()) return;
  isSaving.value = true;
  try {
    const { id, ...attributes } = unitForm.value;
    const { data } = id
      ? await CrmAPI.updateUnit(id, attributes)
      : await CrmAPI.createUnit(attributes);
    dialogRef.value?.close();
    emit('changed');
    selectUnit(data.id);
  } catch (error) {
    useAlert(errorMessage(t, error));
  } finally {
    isSaving.value = false;
  }
};

const toggleActive = async () => {
  try {
    const { data } = await CrmAPI.updateUnit(unit.value.id, {
      active: !unit.value.active,
    });
    unit.value = data;
    emit('changed');
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const addMember = async () => {
  if (!newMemberId.value) return;
  try {
    await CrmAPI.addMember(
      unit.value.id,
      newMemberId.value,
      newMemberRole.value
    );
    newMemberId.value = '';
    await selectUnit(unit.value.id);
    emit('changed');
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const changeRole = async (member, role) => {
  try {
    await CrmAPI.updateMember(unit.value.id, member.id, role);
    await selectUnit(unit.value.id);
    emit('changed');
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

const removeMember = async member => {
  try {
    await CrmAPI.removeMember(unit.value.id, member.id);
    await selectUnit(unit.value.id);
    emit('changed');
  } catch (error) {
    useAlert(errorMessage(t, error));
  }
};

onMounted(() => {
  store.dispatch('agents/get');
  if (props.units.length) selectUnit(props.units[0].id);
});
</script>

<template>
  <SettingsSection
    :title="t('OUTSIDER_CRM.SETTINGS.UNITS.TITLE')"
    :description="t('OUTSIDER_CRM.SETTINGS.UNITS.DESCRIPTION')"
  >
    <template #actions>
      <Button
        icon="i-lucide-plus"
        size="sm"
        :label="t('OUTSIDER_CRM.SETTINGS.UNITS.NEW')"
        @click="openUnitDialog()"
      />
    </template>

    <p
      v-if="!units.length"
      class="p-6 mb-0 text-sm text-center rounded-xl bg-n-alpha-1 text-n-slate-11"
    >
      {{ t('OUTSIDER_CRM.SETTINGS.UNITS.EMPTY') }}
    </p>

    <div v-else class="flex flex-col gap-4 lg:flex-row">
      <div class="flex flex-col gap-1 lg:w-56 shrink-0">
        <button
          v-for="item in units"
          :key="item.id"
          type="button"
          class="flex items-center justify-between gap-2 px-3 py-2 text-sm text-left rounded-lg"
          :class="
            selectedId === item.id
              ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
              : 'text-n-slate-11 hover:bg-n-alpha-1'
          "
          @click="selectUnit(item.id)"
        >
          <span class="truncate">{{ item.name }}</span>
          <span v-if="!item.active" class="text-xs text-n-slate-10">
            {{ t('OUTSIDER_CRM.SETTINGS.INACTIVE') }}
          </span>
        </button>
      </div>

      <div
        v-if="unit"
        class="flex flex-col flex-1 min-w-0 gap-4 p-4 outline outline-1 -outline-offset-1 outline-n-container rounded-xl bg-n-solid-2"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="flex flex-col min-w-0">
            <span class="font-medium text-n-slate-12">{{ unit.name }}</span>
            <span v-if="unit.description" class="text-sm text-n-slate-11">
              {{ unit.description }}
            </span>
          </div>
          <div class="flex items-center gap-3">
            <label class="flex items-center gap-2 text-sm text-n-slate-11">
              {{ t('OUTSIDER_CRM.SETTINGS.ACTIVE') }}
              <Switch :model-value="unit.active" @change="toggleActive" />
            </label>
            <Button
              icon="i-lucide-pencil"
              size="sm"
              variant="ghost"
              color="slate"
              @click="openUnitDialog(unit)"
            />
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <Select
            v-model="newMemberId"
            :options="availableAgents"
            :placeholder="t('OUTSIDER_CRM.SETTINGS.UNITS.ADD_MEMBER')"
          />
          <Select v-model="newMemberRole" :options="roleOptions" />
          <Button
            icon="i-lucide-user-plus"
            size="sm"
            variant="outline"
            :label="t('OUTSIDER_CRM.SETTINGS.UNITS.ADD')"
            :disabled="!newMemberId"
            @click="addMember"
          />
        </div>

        <p v-if="!unit.members.length" class="mb-0 text-sm text-n-slate-11">
          {{ t('OUTSIDER_CRM.SETTINGS.UNITS.NO_MEMBERS') }}
        </p>
        <div
          v-for="member in unit.members"
          :key="member.id"
          class="flex flex-wrap items-center justify-between gap-2 py-2 border-t border-n-weak"
        >
          <div class="flex items-center min-w-0 gap-2">
            <Avatar :name="member.name" :size="28" rounded-full />
            <div class="flex flex-col min-w-0">
              <span class="text-sm truncate text-n-slate-12">
                {{ member.name }}
              </span>
              <span class="text-xs truncate text-n-slate-11">
                {{ member.email }}
              </span>
            </div>
          </div>
          <div class="flex items-center gap-2">
            <Select
              :model-value="member.role"
              :options="roleOptions"
              @update:model-value="role => changeRole(member, role)"
            />
            <Button
              v-tooltip.top="t('OUTSIDER_CRM.SETTINGS.UNITS.REMOVE')"
              icon="i-lucide-trash-2"
              size="sm"
              variant="ghost"
              color="ruby"
              @click="removeMember(member)"
            />
          </div>
        </div>
      </div>
    </div>

    <Dialog
      ref="dialogRef"
      :title="
        unitForm.id
          ? t('OUTSIDER_CRM.SETTINGS.UNITS.EDIT')
          : t('OUTSIDER_CRM.SETTINGS.UNITS.NEW')
      "
      :confirm-button-label="t('OUTSIDER_CRM.SAVE')"
      :is-loading="isSaving"
      :disable-confirm-button="!unitForm.name.trim()"
      @confirm="saveUnit"
    >
      <div class="flex flex-col gap-4">
        <Input
          v-model="unitForm.name"
          :label="t('OUTSIDER_CRM.SETTINGS.UNITS.NAME')"
          :placeholder="t('OUTSIDER_CRM.SETTINGS.UNITS.NAME_PLACEHOLDER')"
        />
        <Input
          v-model="unitForm.description"
          :label="t('OUTSIDER_CRM.SETTINGS.UNITS.UNIT_DESCRIPTION')"
        />
      </div>
    </Dialog>
  </SettingsSection>
</template>
