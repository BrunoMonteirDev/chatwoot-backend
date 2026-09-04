export const dashboardAppSidebarChildren = (
  dashboardApps,
  accountId,
  accountScopedRoute
) =>
  dashboardApps
    .filter(
      app =>
        app.enabled &&
        (!app.account_id || Number(app.account_id) === Number(accountId))
    )
    .map(app => ({
      name: `App-${app.id}`,
      label: app.title,
      icon: app.icon || 'i-lucide-panels-top-left',
      to: accountScopedRoute('dashboard_apps_launcher', { appId: app.id }),
    }));
