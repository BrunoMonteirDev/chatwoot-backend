<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { debounce } from '@chatwoot/utils';
import { useRouter } from 'vue-router';
import SearchAPI from 'dashboard/api/search';
import { useAccount } from 'dashboard/composables/useAccount';

defineProps({ isCollapsed: { type: Boolean, default: false } });
const emit = defineEmits(['closeMobileSidebar']);
const router = useRouter();
const { accountId } = useAccount();
const isOpen = ref(false);
const query = ref('');
const contacts = ref([]);
const conversations = ref([]);
const isLoading = ref(false);
const hasError = ref(false);
let controller;
let requestId = 0;

const hasResults = computed(
  () => contacts.value.length || conversations.value.length
);
const canSearch = computed(() => query.value.trim().length >= 2);

const resetResults = () => {
  contacts.value = [];
  conversations.value = [];
  hasError.value = false;
};

const search = async value => {
  if (!value || value.length < 2) {
    controller?.abort();
    isLoading.value = false;
    resetResults();
    return;
  }
  controller?.abort();
  controller = new AbortController();
  requestId += 1;
  const id = requestId;
  isLoading.value = true;
  hasError.value = false;
  try {
    const [contactResponse, conversationResponse] = await Promise.all([
      SearchAPI.contacts({ q: value, signal: controller.signal }),
      SearchAPI.conversations({ q: value, signal: controller.signal }),
    ]);
    if (id !== requestId) return;
    contacts.value = contactResponse.data.payload.contacts;
    conversations.value = conversationResponse.data.payload.conversations;
  } catch (error) {
    if (id === requestId && error.name !== 'CanceledError')
      hasError.value = true;
  } finally {
    if (id === requestId) isLoading.value = false;
  }
};

const debouncedSearch = debounce(search, 300);
watch(query, value => debouncedSearch(value.trim()));

const close = () => {
  isOpen.value = false;
  controller?.abort();
};
const open = () => {
  isOpen.value = true;
};
const openConversation = conversation => {
  router.push({
    name: 'inbox_conversation',
    params: { accountId: accountId.value, conversation_id: conversation.id },
  });
  emit('closeMobileSidebar');
  close();
};
const openContact = contact => {
  router.push({
    name: 'contacts_edit',
    params: { accountId: accountId.value, contactId: contact.id },
  });
  emit('closeMobileSidebar');
  close();
};
onBeforeUnmount(() => controller?.abort());
</script>

<template>
  <button
    type="button"
    class="flex gap-2 items-center px-2 py-1 w-full h-7 rounded-lg outline outline-1 outline-n-weak bg-n-button-color transition-all duration-100 ease-out"
    :class="isCollapsed ? 'justify-center !w-8 !h-8' : ''"
    :title="isCollapsed ? $t('SIDEBAR.SEARCH') : undefined"
    @click="open"
  >
    <span class="flex-shrink-0 i-lucide-search size-4 text-n-slate-10" />
    <span v-if="!isCollapsed" class="flex-grow text-start text-n-slate-10">{{
      $t('SIDEBAR.SEARCH')
    }}</span>
  </button>
  <Teleport to="body">
    <div
      v-if="isOpen"
      class="fixed inset-0 z-50 flex items-start justify-center bg-n-alpha-black2 p-4 pt-16"
      @click.self="close"
    >
      <section class="w-full max-w-xl rounded-xl bg-n-surface-1 shadow-xl">
        <div class="flex items-center gap-2 border-b border-n-weak p-3">
          <span class="i-lucide-search size-4 text-n-slate-10" />
          <input
            v-model="query"
            autofocus
            class="m-0 flex-1 border-0 bg-transparent p-0 text-sm outline-none"
            :placeholder="$t('SIDEBAR.SEARCH_PLACEHOLDER')"
            @keydown.esc="close"
          />
          <button
            type="button"
            class="i-lucide-x size-4 text-n-slate-10"
            :title="$t('GENERAL.CLOSE')"
            @click="close"
          />
        </div>
        <div class="max-h-[60vh] overflow-y-auto p-3">
          <p v-if="!canSearch" class="py-6 text-center text-sm text-n-slate-11">
            {{ $t('SIDEBAR.SEARCH_MINIMUM') }}
          </p>
          <p
            v-else-if="isLoading"
            class="py-6 text-center text-sm text-n-slate-11"
          >
            {{ $t('SIDEBAR.SEARCH_LOADING') }}
          </p>
          <p
            v-else-if="hasError"
            class="py-6 text-center text-sm text-n-slate-11"
          >
            {{ $t('SIDEBAR.SEARCH_ERROR') }}
          </p>
          <p
            v-else-if="!hasResults"
            class="py-6 text-center text-sm text-n-slate-11"
          >
            {{ $t('SIDEBAR.SEARCH_EMPTY') }}
          </p>
          <template v-else>
            <div v-if="conversations.length" class="mb-4">
              <h3 class="mb-2 text-xs font-medium text-n-slate-11">
                {{ $t('SIDEBAR.SEARCH_CONVERSATIONS') }}
              </h3>
              <button
                v-for="conversation in conversations"
                :key="conversation.id"
                type="button"
                class="flex w-full flex-col rounded-lg p-2 text-left hover:bg-n-alpha-2"
                @click="openConversation(conversation)"
              >
                <span class="text-sm text-n-slate-12">{{
                  conversation.contact?.name ||
                  conversation.contact?.phone_number ||
                  `#${conversation.id}`
                }}</span>
                <span class="truncate text-xs text-n-slate-11">{{
                  conversation.inbox?.name
                }}</span>
              </button>
            </div>
            <div v-if="contacts.length">
              <h3 class="mb-2 text-xs font-medium text-n-slate-11">
                {{ $t('SIDEBAR.SEARCH_CONTACTS') }}
              </h3>
              <button
                v-for="contact in contacts"
                :key="contact.id"
                type="button"
                class="flex w-full flex-col rounded-lg p-2 text-left hover:bg-n-alpha-2"
                @click="openContact(contact)"
              >
                <span class="text-sm text-n-slate-12">{{ contact.name }}</span>
                <span class="truncate text-xs text-n-slate-11">{{
                  contact.phone_number || contact.email
                }}</span>
              </button>
            </div>
          </template>
        </div>
      </section>
    </div>
  </Teleport>
</template>
