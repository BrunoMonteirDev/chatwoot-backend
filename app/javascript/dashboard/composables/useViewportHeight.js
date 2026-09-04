import { onBeforeUnmount, onMounted } from 'vue';

const VIEWPORT_HEIGHT_VARIABLE = '--app-viewport-height';

export const useViewportHeight = elementRef => {
  let visualViewport = null;

  const updateViewportHeight = () => {
    const height = visualViewport?.height ?? window.innerHeight;
    elementRef.value?.style.setProperty(
      VIEWPORT_HEIGHT_VARIABLE,
      `${Math.round(height)}px`
    );
  };

  onMounted(() => {
    visualViewport = window.visualViewport;
    updateViewportHeight();

    window.addEventListener('resize', updateViewportHeight);
    visualViewport?.addEventListener('resize', updateViewportHeight);
  });

  onBeforeUnmount(() => {
    window.removeEventListener('resize', updateViewportHeight);
    visualViewport?.removeEventListener('resize', updateViewportHeight);
  });
};
