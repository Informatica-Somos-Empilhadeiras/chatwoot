// app/javascript/dashboard/store/modules/conversations/actions/conversationPinActions.js
import ConversationApi from 'dashboard/api/inbox/conversation';
import types from '../../../mutation-types';

export default {
    toggleConversationPin: async ({ commit }, conversation) => {
        const isPinned = !!conversation.custom_attributes?.pinned;
        const customAttributes = {
            ...conversation.custom_attributes,
            pinned: !isPinned,
        };
        await ConversationApi.updateCustomAttributes({
            conversationId: conversation.id,
            customAttributes,
        });
        commit(types.UPDATE_CONVERSATION_CUSTOM_ATTRIBUTES, {
            conversationId: conversation.id,
            customAttributes,
        });
    },
};
