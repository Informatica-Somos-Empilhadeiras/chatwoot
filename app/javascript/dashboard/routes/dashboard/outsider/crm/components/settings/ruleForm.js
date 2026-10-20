// OUTSIDER: regra de automação (ver app/services/outsider/crm/automation_rules.rb) entre a API e o
// formulário da tela: tempos em horas viram "quantidade + horas/dias" e o valor mínimo em centavos
// vira reais. Também traduz os códigos de erro que a API devolve.
export const RULE_TRIGGERS = [
  'created',
  'stage_entered',
  'won',
  'lost',
  'stalled',
  'no_next_task',
];
export const TIMED_TRIGGERS = ['stalled', 'no_next_task'];
export const RULE_ACTIONS = [
  'create_task',
  'set_owner',
  'add_label',
  'add_note',
];
export const ASSIGNEES = ['owner', 'managers', 'user'];
export const MAX_RULE_ACTIONS = 5;
export const MAX_HOURS = 2160;

export const ACTION_ICONS = {
  create_task: 'i-lucide-list-checks',
  set_owner: 'i-lucide-user-round-cog',
  add_label: 'i-lucide-tag',
  add_note: 'i-lucide-sticky-note',
};

// 48 horas aparecem como 2 dias; o que não fecha em dias fica em horas
export const splitHours = hours => {
  const value = Number(hours) || 0;
  return value && value % 24 === 0
    ? { amount: value / 24, unit: 'days' }
    : { amount: value, unit: 'hours' };
};

export const joinHours = (amount, unit) =>
  Math.round(Number(amount) || 0) * (unit === 'days' ? 24 : 1);

export const centsToInput = cents =>
  cents === null || cents === undefined
    ? ''
    : (cents / 100).toFixed(2).replace('.', ',');

// "1.500,50" ou "1500.5" → 150050; vazio → sem valor mínimo
export const inputToCents = text => {
  let value = String(text ?? '').trim();
  if (!value) return null;
  if (value.includes(',')) value = value.replace(/\./g, '').replace(',', '.');
  const number = Number(value);
  return Number.isFinite(number) && number >= 0
    ? Math.round(number * 100)
    : NaN;
};

export const blankAction = (type = 'create_task') => ({
  type,
  title: '',
  kind: 'follow_up',
  description: '',
  due_amount: 1,
  due_unit: 'days',
  assignee: 'owner',
  user_id: '',
  label: '',
  body: '',
});

export const blankForm = () => ({
  name: '',
  active: true,
  trigger: 'stage_entered',
  wait_amount: 3,
  wait_unit: 'days',
  business_unit_id: '',
  pipeline_id: '',
  stage_id: '',
  min_value: '',
  actions: [blankAction()],
});

const actionToForm = action => {
  const due = splitHours(action.due_in_hours);
  return {
    ...blankAction(action.type),
    ...action,
    description: action.description || '',
    due_amount: due.amount,
    due_unit: due.unit,
    user_id: action.user_id || '',
  };
};

export const ruleToForm = rule => {
  const wait = splitHours(rule.wait_hours || 72);
  const conditions = rule.conditions || {};
  return {
    name: rule.name,
    active: rule.active,
    trigger: rule.trigger,
    wait_amount: wait.amount,
    wait_unit: wait.unit,
    business_unit_id: conditions.business_unit_id || '',
    pipeline_id: conditions.pipeline_id || '',
    stage_id: conditions.stage_id || '',
    min_value: centsToInput(conditions.min_value_cents),
    actions: rule.actions.map(actionToForm),
  };
};

const formToAction = action => {
  switch (action.type) {
    case 'create_task':
      return {
        type: action.type,
        title: action.title.trim(),
        kind: action.kind,
        description: action.description.trim(),
        due_in_hours: joinHours(action.due_amount, action.due_unit),
        assignee: action.assignee,
        user_id: action.assignee === 'user' ? action.user_id : null,
      };
    case 'set_owner':
      return { type: action.type, user_id: action.user_id };
    case 'add_label':
      return { type: action.type, label: action.label };
    default:
      return { type: action.type, body: action.body.trim() };
  }
};

export const formToRule = form => ({
  name: form.name.trim(),
  active: form.active,
  trigger: form.trigger,
  wait_hours: TIMED_TRIGGERS.includes(form.trigger)
    ? joinHours(form.wait_amount, form.wait_unit)
    : null,
  conditions: {
    business_unit_id: form.business_unit_id || null,
    pipeline_id: form.pipeline_id || null,
    stage_id: form.stage_id || null,
    min_value_cents: inputToCents(form.min_value),
  },
  actions: form.actions.map(formToAction),
});

const hoursInRange = (hours, min) => hours >= min && hours <= MAX_HOURS;

const actionValid = action => {
  switch (action.type) {
    case 'create_task':
      return (
        action.title.trim() &&
        hoursInRange(joinHours(action.due_amount, action.due_unit), 0) &&
        (action.assignee !== 'user' || action.user_id)
      );
    case 'set_owner':
      return action.user_id;
    case 'add_label':
      return action.label;
    default:
      return action.body.trim();
  }
};

export const isFormValid = form =>
  Boolean(
    form.name.trim() &&
      RULE_TRIGGERS.includes(form.trigger) &&
      (!TIMED_TRIGGERS.includes(form.trigger) ||
        hoursInRange(joinHours(form.wait_amount, form.wait_unit), 1)) &&
      !Number.isNaN(inputToCents(form.min_value)) &&
      form.actions.length &&
      form.actions.every(actionValid)
  );

// "actions.1.title_blank" → "Ação 2: ..."
const FIELD_ERRORS = {
  name_blank: 'NAME',
  name_too_long: 'NAME',
  trigger_invalid: 'TRIGGER',
  wait_hours: 'WAIT',
  actions_blank: 'ACTIONS',
  too_many_actions: 'ACTIONS',
  too_many_rules: 'TOO_MANY',
  title_blank: 'TASK_TITLE',
  title_too_long: 'TASK_TITLE',
  due_in_hours: 'TASK_DUE',
  user_id: 'USER',
  label: 'LABEL',
  body_blank: 'NOTE',
  body_too_long: 'NOTE',
};

export const ruleErrorMessage = (t, field) => {
  const prefix = 'OUTSIDER_CRM.SETTINGS.RULES.ERRORS';
  if (field.startsWith('conditions.')) return t(`${prefix}.CONDITIONS`);
  const match = field.match(/^actions\.(\d+)\.(.+)$/);
  const key = FIELD_ERRORS[match ? match[2] : field] || 'GENERIC';
  const message = t(`${prefix}.${key}`);
  return match
    ? t(`${prefix}.ACTION`, { number: Number(match[1]) + 1, message })
    : message;
};
