import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import SidebarGlobalSearch from '../SidebarGlobalSearch.vue';

const { push, contacts, conversations } = vi.hoisted(() => ({
  push: vi.fn(),
  contacts: vi.fn(),
  conversations: vi.fn(),
}));

vi.mock('dashboard/api/search', () => ({
  default: { contacts, conversations },
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: { value: 1 } }),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));

const mountSearch = () =>
  mount(SidebarGlobalSearch, {
    global: { mocks: { $t: key => key }, stubs: { Teleport: true } },
  });

describe('SidebarGlobalSearch', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    contacts.mockReset();
    conversations.mockReset();
    push.mockReset();
  });

  afterEach(() => vi.useRealTimers());

  it('debounces grouped contact and conversation results', async () => {
    contacts.mockResolvedValue({
      data: { payload: { contacts: [{ id: 2, name: 'Maria' }] } },
    });
    conversations.mockResolvedValue({
      data: {
        payload: {
          conversations: [
            { id: 3, contact: { name: 'João' }, inbox: { name: 'Sales' } },
          ],
        },
      },
    });
    const wrapper = mountSearch();
    await wrapper.find('button').trigger('click');
    await wrapper.find('input').setValue('jo');
    expect(contacts).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(300);

    expect(contacts).toHaveBeenCalledWith(expect.objectContaining({ q: 'jo' }));
    expect(wrapper.text()).toContain('SIDEBAR.SEARCH_CONVERSATIONS');
    expect(wrapper.text()).toContain('SIDEBAR.SEARCH_CONTACTS');
  });

  it('does not let a stale request replace newer results', async () => {
    let resolveFirst;
    contacts.mockReturnValueOnce(
      new Promise(resolve => {
        resolveFirst = resolve;
      })
    );
    conversations.mockReturnValueOnce(
      new Promise(resolve => {
        resolveFirst = resolve;
      })
    );
    contacts.mockResolvedValueOnce({
      data: { payload: { contacts: [{ id: 4, name: 'New' }] } },
    });
    conversations.mockResolvedValueOnce({
      data: { payload: { conversations: [] } },
    });
    const wrapper = mountSearch();
    await wrapper.find('button').trigger('click');
    const input = wrapper.find('input');
    await input.setValue('old');
    await vi.advanceTimersByTimeAsync(300);
    await input.setValue('new');
    await vi.advanceTimersByTimeAsync(300);
    resolveFirst?.({
      data: {
        payload: { contacts: [{ id: 5, name: 'Old' }], conversations: [] },
      },
    });
    await nextTick();

    expect(wrapper.text()).toContain('New');
    expect(wrapper.text()).not.toContain('Old');
  });
});
