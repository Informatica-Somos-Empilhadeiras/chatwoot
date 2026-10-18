// OUTSIDER: conversas fixadas por pessoa. Cada agente fixa as suas, sem mexer na lista
// dos outros. Ficam nas preferências do usuário (ui_settings), separadas por conta,
// então valem em qualquer computador em que ele entrar.
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';

const SETTINGS_KEY = 'outsider_pinned_conversations';

export function useConversationPins() {
  const { uiSettings, updateUISettings } = useUISettings();
  const accountId = useMapGetter('getCurrentAccountId');

  const pinnedIds = computed(
    () => uiSettings.value[SETTINGS_KEY]?.[accountId.value] || []
  );

  const isPinned = id => pinnedIds.value.includes(id);

  const togglePin = id => {
    const ids = isPinned(id)
      ? pinnedIds.value.filter(pinnedId => pinnedId !== id)
      : [...pinnedIds.value, id];
    updateUISettings({
      [SETTINGS_KEY]: {
        ...uiSettings.value[SETTINGS_KEY],
        [accountId.value]: ids,
      },
    });
  };

  return { isPinned, togglePin };
}
