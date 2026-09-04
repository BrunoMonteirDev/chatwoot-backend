<script setup>
import { computed, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import DashboardAppFrame from 'dashboard/components/widgets/DashboardApp/Frame.vue';

const route = useRoute();
const store = useStore();
const dashboardApps = useMapGetter('dashboardApps/getRecords');
const uiFlags = useMapGetter('dashboardApps/getUIFlags');

const appId = computed(() => Number(route.params.appId));
const dashboardApp = computed(() =>
  dashboardApps.value.find(app => app.id === appId.value && app.enabled)
);
const isLoading = computed(() => uiFlags.value.isFetching);

watch(
  () => route.params.accountId,
  () => store.dispatch('dashboardApps/get'),
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-1 min-w-0 min-h-0 bg-n-surface-1">
    <DashboardAppFrame
      v-if="dashboardApp"
      :config="dashboardApp.content"
      is-visible
      :position="0"
      class="flex-1 min-w-0 min-h-0"
    />
    <div
      v-else-if="isLoading"
      class="flex flex-1 items-center justify-center text-sm text-n-slate-11"
    >
      {{ $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.LIST.LOADING') }}
    </div>
    <div
      v-else
      class="flex flex-1 items-center justify-center text-sm text-n-slate-11"
    >
      {{ $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.UNAVAILABLE') }}
    </div>
  </div>
</template>
