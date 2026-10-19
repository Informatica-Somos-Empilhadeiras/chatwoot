<script setup>
// OUTSIDER: campo personalizado da oportunidade, do tipo definido em Configurações > Campos.
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const props = defineProps({
  field: { type: Object, required: true },
  disabled: { type: Boolean, default: false },
});

const value = defineModel({ type: [String, Number, Boolean], default: '' });

const options = () =>
  props.field.options.map(option => ({ value: option, label: option }));
</script>

<template>
  <div class="flex flex-col gap-1">
    <span class="text-sm font-medium text-n-slate-12">
      {{ field.label
      }}<span v-if="field.required" class="text-n-ruby-9">*</span>
    </span>
    <Select
      v-if="field.field_type === 'list'"
      v-model="value"
      :options="options()"
      :disabled="disabled"
      placeholder="—"
      class="[&>select]:w-full !w-full"
    />
    <Switch
      v-else-if="field.field_type === 'checkbox'"
      v-model="value"
      :disabled="disabled"
    />
    <Input
      v-else
      v-model="value"
      :type="field.field_type === 'date' ? 'date' : 'text'"
      :disabled="disabled"
      :placeholder="field.field_type === 'currency' ? '0,00' : ''"
    />
  </div>
</template>
