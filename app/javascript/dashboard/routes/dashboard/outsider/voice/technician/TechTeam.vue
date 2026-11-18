<script setup>
// OUTSIDER (técnicos): aba Ramais do Meu telefone. A empresa por filial, com quem está livre, em ligação, ocupado ou
// com o app fechado (toca pelo aviso no celular). Um toque liga.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { phone, dial } from '../phone';
import TechHeader from './TechHeader.vue';
import { presenceOf, techState } from './techStore';

const { t } = useI18n();
const search = ref('');
const branch = ref('');

const NO_BRANCH = '';

const people = computed(() =>
  techState.team.filter(person => person.id !== phone.userId)
);
const branches = computed(() =>
  [...new Set(people.value.map(person => person.branch).filter(Boolean))].sort(
    (a, b) => a.localeCompare(b)
  )
);

const normalize = value =>
  String(value || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();

const filtered = computed(() => {
  const query = normalize(search.value.trim());
  return people.value.filter(person => {
    if (branch.value && person.branch !== branch.value) return false;
    if (!query) return true;
    return [person.name, person.extension, person.branch].some(value =>
      normalize(value).includes(query)
    );
  });
});

const groups = computed(() => {
  const map = new Map();
  filtered.value.forEach(person => {
    const key = person.branch || NO_BRANCH;
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(person);
  });
  return [...map.entries()]
    .sort(([a], [b]) => {
      if (a === NO_BRANCH) return 1;
      if (b === NO_BRANCH) return -1;
      return a.localeCompare(b);
    })
    .map(([name, list]) => ({
      name: name || t('OUTSIDER_VOICE.TECH.NO_BRANCH'),
      list,
    }));
});

const callable = person => !['in_call', 'offline'].includes(presenceOf(person));

const call = person => {
  const error = dial(person.extension);
  if (error) useAlert(t(`OUTSIDER_VOICE.PHONE.ERRORS.${error}`));
};
</script>

<template>
  <div>
    <TechHeader :title="t('OUTSIDER_VOICE.TECH.TABS.TEAM')" />
    <label
      class="flex items-center gap-2 px-3 py-2.5 mx-4 mt-3 rounded-xl bg-n-alpha-2 text-n-slate-11"
    >
      <span class="i-lucide-search size-4 shrink-0" />
      <input
        v-model="search"
        type="search"
        class="flex-1 min-w-0 !m-0 !p-0 !border-0 !bg-transparent !h-auto text-sm text-n-slate-12 !outline-none"
        :placeholder="t('OUTSIDER_VOICE.TECH.SEARCH')"
        data-testid="outsider-tech-search"
      />
    </label>
    <div
      v-if="branches.length > 1"
      class="flex gap-2 px-4 pt-3 pb-1 overflow-x-auto"
    >
      <button
        type="button"
        class="outsider-tech-chip"
        :class="{ 'is-on': !branch }"
        @click="branch = ''"
      >
        {{ t('OUTSIDER_VOICE.TECH.ALL') }}
      </button>
      <button
        v-for="name in branches"
        :key="name"
        type="button"
        class="outsider-tech-chip"
        :class="{ 'is-on': branch === name }"
        @click="branch = name"
      >
        {{ name }}
      </button>
    </div>

    <p
      v-if="!filtered.length"
      class="px-6 py-10 text-sm text-center text-n-slate-11"
    >
      {{
        techState.teamAt
          ? t('OUTSIDER_VOICE.TECH.TEAM_EMPTY')
          : t('OUTSIDER_VOICE.TECH.LOADING')
      }}
    </p>

    <section v-for="group in groups" :key="group.name">
      <h2
        class="px-4 pt-4 pb-1 text-xs font-bold tracking-wide uppercase text-n-slate-11"
      >
        {{ group.name }}
      </h2>
      <div
        v-for="person in group.list"
        :key="person.id"
        class="flex items-center gap-3 px-4 py-2.5"
        :data-testid="`outsider-tech-person-${person.extension}`"
      >
        <span class="relative shrink-0">
          <Avatar
            :name="person.name"
            :src="person.thumbnail || ''"
            :size="42"
            rounded-full
          />
          <span
            class="outsider-tech-presence"
            :class="`is-${presenceOf(person)}`"
          />
        </span>
        <span class="flex-1 min-w-0">
          <span class="block font-semibold truncate text-n-slate-12">
            {{ person.name }}
          </span>
          <span class="block text-xs truncate text-n-slate-11">
            {{ person.extension }} ·
            {{
              t(
                `OUTSIDER_VOICE.TECH.PRESENCE.${presenceOf(person).toUpperCase()}`
              )
            }}
          </span>
        </span>
        <button
          type="button"
          class="outsider-tech-round"
          :class="{ 'is-off': !callable(person) }"
          :disabled="!callable(person)"
          :aria-label="t('OUTSIDER_VOICE.TECH.CALL_TO', { name: person.name })"
          @click="call(person)"
        >
          <span class="i-lucide-phone size-5" />
        </button>
      </div>
    </section>
    <div class="h-4" />
  </div>
</template>

<style scoped>
.outsider-tech-chip {
  flex: none;
  padding: 0.35rem 0.8rem;
  border-radius: 999px;
  font-size: 0.8rem;
  font-weight: 500;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}

.outsider-tech-chip.is-on {
  background: var(--outsider-brand, #00663b);
  color: #fff;
}

.outsider-tech-presence {
  position: absolute;
  right: -1px;
  bottom: -1px;
  width: 0.8rem;
  height: 0.8rem;
  border-radius: 50%;
  border: 2px solid rgb(var(--solid-1, 255 255 255));
  background: #94a3b8;
}

.outsider-tech-presence.is-online {
  background: #22c55e;
}

.outsider-tech-presence.is-in_call {
  background: #ef4444;
}

.outsider-tech-presence.is-busy,
.outsider-tech-presence.is-push {
  background: #f59e0b;
}

.outsider-tech-round {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 2.5rem;
  height: 2.5rem;
  flex: none;
  border-radius: 50%;
  background: #e8f7ee;
  color: #137333;
}

.outsider-tech-round.is-off {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-9));
}
</style>
