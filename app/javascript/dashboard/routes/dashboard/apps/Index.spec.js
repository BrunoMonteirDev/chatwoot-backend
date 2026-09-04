import { mount } from '@vue/test-utils';
import { nextTick, reactive, ref } from 'vue';
import AppLauncher from './Index.vue';

const route = reactive({ params: { accountId: '1', appId: '10' } });
const dashboardApps = ref([]);
const uiFlags = ref({ isFetching: false });
const dispatch = vi.fn();

vi.mock('vue-router', () => ({
  useRoute: () => route,
}));

vi.mock('vuex', () => ({
  useStore: () => ({ dispatch }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key =>
    key === 'dashboardApps/getRecords' ? dashboardApps : uiFlags,
}));

const mountLauncher = () =>
  mount(AppLauncher, {
    global: {
      mocks: { $t: key => key },
      stubs: {
        DashboardAppFrame: {
          props: ['config'],
          template:
            '<div data-test-id="dashboard-app-frame" :data-config="JSON.stringify(config)" />',
        },
      },
    },
  });

describe('Dashboard app launcher', () => {
  beforeEach(() => {
    route.params.accountId = '1';
    route.params.appId = '10';
    dashboardApps.value = [];
    uiFlags.value = { isFetching: false };
    dispatch.mockClear();
  });

  it('opens the enabled app addressed by the URL', async () => {
    dashboardApps.value = [
      {
        id: 10,
        enabled: true,
        content: [{ type: 'frame', url: 'https://crm.test' }],
      },
      {
        id: 11,
        enabled: true,
        content: [{ type: 'frame', url: 'https://meta.test' }],
      },
    ];
    const wrapper = mountLauncher();

    expect(dispatch).toHaveBeenCalledWith('dashboardApps/get');
    expect(wrapper.find('[data-test-id="dashboard-app-frame"]').exists()).toBe(
      true
    );

    route.params.appId = '11';
    await nextTick();
    expect(
      wrapper
        .find('[data-test-id="dashboard-app-frame"]')
        .attributes('data-config')
    ).toContain('https://meta.test');
  });

  it('does not render an iframe for disabled or missing apps', () => {
    dashboardApps.value = [{ id: 10, enabled: false, content: [] }];
    const wrapper = mountLauncher();

    expect(wrapper.find('[data-test-id="dashboard-app-frame"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).toContain(
      'INTEGRATION_SETTINGS.DASHBOARD_APPS.UNAVAILABLE'
    );
  });
});
