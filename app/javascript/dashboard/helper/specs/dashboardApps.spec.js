import { dashboardAppSidebarChildren } from '../dashboardApps';

const routeForAccount = (name, params) => ({
  name,
  params: { accountId: 1, ...params },
});

describe('dashboardAppSidebarChildren', () => {
  it('creates one route per enabled app without administrative actions', () => {
    const children = dashboardAppSidebarChildren(
      [
        { id: 10, title: 'CRM', enabled: true },
        { id: 11, title: 'MetaHub', enabled: true },
      ],
      1,
      routeForAccount
    );

    expect(children).toEqual([
      {
        name: 'App-10',
        label: 'CRM',
        icon: 'i-lucide-panels-top-left',
        to: {
          name: 'dashboard_apps_launcher',
          params: { accountId: 1, appId: 10 },
        },
      },
      {
        name: 'App-11',
        label: 'MetaHub',
        icon: 'i-lucide-panels-top-left',
        to: {
          name: 'dashboard_apps_launcher',
          params: { accountId: 1, appId: 11 },
        },
      },
    ]);
  });

  it('excludes disabled apps and apps from another account', () => {
    const children = dashboardAppSidebarChildren(
      [
        { id: 10, title: 'Enabled', enabled: true, account_id: 1 },
        { id: 11, title: 'Disabled', enabled: false, account_id: 1 },
        { id: 12, title: 'Other account', enabled: true, account_id: 2 },
      ],
      1,
      routeForAccount
    );

    expect(children.map(child => child.label)).toEqual(['Enabled']);
  });
});
