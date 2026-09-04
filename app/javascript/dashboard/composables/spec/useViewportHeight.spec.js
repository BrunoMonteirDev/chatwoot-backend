const viewportHeightMock = vi.hoisted(() => ({
  mountedCallbacks: [],
  unmountedCallbacks: [],
}));

vi.mock('vue', async importOriginal => ({
  ...(await importOriginal()),
  onMounted: vi.fn(callback =>
    viewportHeightMock.mountedCallbacks.push(callback)
  ),
  onBeforeUnmount: vi.fn(callback =>
    viewportHeightMock.unmountedCallbacks.push(callback)
  ),
}));

import { useViewportHeight } from '../useViewportHeight';

describe('useViewportHeight', () => {
  let visualViewport;
  let elementRef;

  beforeEach(() => {
    viewportHeightMock.mountedCallbacks = [];
    viewportHeightMock.unmountedCallbacks = [];
    visualViewport = new EventTarget();
    Object.defineProperty(visualViewport, 'height', {
      configurable: true,
      value: 800,
      writable: true,
    });
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: visualViewport,
    });
    elementRef = { value: document.createElement('div') };
  });

  afterEach(() => {
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: undefined,
    });
  });

  it('updates the app height when the visual viewport resizes', () => {
    useViewportHeight(elementRef);
    viewportHeightMock.mountedCallbacks[0]();

    expect(
      elementRef.value.style.getPropertyValue('--app-viewport-height')
    ).toBe('800px');

    visualViewport.height = 480;
    visualViewport.dispatchEvent(new Event('resize'));

    expect(
      elementRef.value.style.getPropertyValue('--app-viewport-height')
    ).toBe('480px');
  });

  it('registers one visual viewport listener and removes it on unmount', () => {
    const addEventListener = vi.spyOn(visualViewport, 'addEventListener');
    const removeEventListener = vi.spyOn(visualViewport, 'removeEventListener');

    useViewportHeight(elementRef);
    viewportHeightMock.mountedCallbacks[0]();

    expect(addEventListener).toHaveBeenCalledTimes(1);
    expect(addEventListener).toHaveBeenCalledWith(
      'resize',
      expect.any(Function)
    );

    viewportHeightMock.unmountedCallbacks[0]();

    expect(removeEventListener).toHaveBeenCalledTimes(1);
    expect(removeEventListener).toHaveBeenCalledWith(
      'resize',
      expect.any(Function)
    );
  });

  it('uses the window height when VisualViewport is unavailable', () => {
    Object.defineProperty(window, 'visualViewport', {
      configurable: true,
      value: undefined,
    });
    Object.defineProperty(window, 'innerHeight', {
      configurable: true,
      value: 900,
      writable: true,
    });

    useViewportHeight(elementRef);
    viewportHeightMock.mountedCallbacks[0]();

    expect(
      elementRef.value.style.getPropertyValue('--app-viewport-height')
    ).toBe('900px');
  });
});
