import { requireOptionalNativeModule } from 'expo';
import type { ComponentRef } from 'react';
import { findNodeHandle, Platform, type View } from 'react-native';

export type PhotoViewerItem = {
  /** Unique within this gallery. */
  key: string;
  /** Local file:// URL for the full-resolution image, if already available. */
  uri?: string;
  /** Local file:// URL shown while loadPhoto resolves the full image. */
  previewUri?: string;
  /** Dimensions reserve the correct aspect ratio before decoding. */
  width?: number;
  height?: number;
  /** Mounted, non-collapsible native thumbnail wrapper for the zoom transition. */
  source?: ComponentRef<typeof View> | null;
};

export type PhotoViewerLabels = {
  close?: string;
  retry?: string;
  unavailable?: string;
  /** A template containing {current} and {total}. */
  position?: string;
};

export type OpenPhotoViewerOptions = {
  photos: readonly PhotoViewerItem[];
  initialIndex?: number;
  caption?: string;
  labels?: PhotoViewerLabels;
  /** Resolve a local file:// URL. Return null for an unavailable photo, or throw to allow retry. */
  loadPhoto?: (photo: PhotoViewerItem, request: { retry: boolean }) => Promise<string | null>;
  onClose?: () => void;
  /** Aborting dismisses this gallery and discards outstanding image results. */
  signal?: AbortSignal;
};

type NativeItem = {
  key: string;
  width: number;
  height: number;
  sourceTag: number | null;
  previewUri: string | null;
  fullUri: string | null;
};

type NativeEvents = {
  onClose: { session: string };
  onRequestPhoto: { session: string; key: string; retry: boolean };
};

type NativeViewer = {
  isSupported: boolean;
  present(
    session: string,
    items: NativeItem[],
    index: number,
    caption: string | null,
    labels: PhotoViewerLabels
  ): Promise<boolean>;
  setPhoto(session: string, key: string, uri: string | null, unavailable: boolean): Promise<void>;
  dismiss(session: string): Promise<void>;
  addListener<K extends keyof NativeEvents>(
    event: K,
    listener: (event: NativeEvents[K]) => void
  ): { remove(): void };
};

const nativeViewer =
  Platform.OS === 'ios' ? requireOptionalNativeModule<NativeViewer>('ExpoPhotoViewer') : null;
let nextSession = 0;
let activeSession: string | undefined;

/** Whether the native viewer is available in the current build and OS. */
export function isPhotoViewerSupported(): boolean {
  return nativeViewer?.isSupported === true;
}

/** Present a gallery. Returns false if it could not be opened. Only one gallery can be open at a time. */
export async function openPhotoViewer({
  photos,
  initialIndex = 0,
  caption,
  labels = {},
  loadPhoto,
  onClose,
  signal,
}: OpenPhotoViewerOptions): Promise<boolean> {
  const viewer = nativeViewer;
  if (
    !viewer?.isSupported ||
    activeSession ||
    signal?.aborted ||
    !Number.isInteger(initialIndex) ||
    !photos[initialIndex]
  ) {
    return false;
  }

  const itemsByKey = new Map(photos.map((photo) => [photo.key, photo]));
  if (itemsByKey.size !== photos.length) return false;

  const items = photos.map((photo): NativeItem => ({
    key: photo.key,
    width: photo.width ?? 0,
    height: photo.height ?? 0,
    sourceTag: photo.source ? (findNodeHandle(photo.source) ?? null) : null,
    previewUri: photo.previewUri ?? photo.uri ?? null,
    fullUri: photo.uri ?? null,
  }));
  const session = String(++nextSession);
  let presented = false;
  const subscriptions: { remove(): void }[] = [];
  activeSession = session;

  function release() {
    if (activeSession !== session) return;
    activeSession = undefined;
    signal?.removeEventListener('abort', abort);
    for (const subscription of subscriptions) subscription.remove();
  }

  function abort() {
    if (presented) viewer?.dismiss(session).catch(release);
  }

  subscriptions.push(
    viewer.addListener('onClose', (event) => {
      if (event.session !== session) return;
      release();
      onClose?.();
    }),
    viewer.addListener('onRequestPhoto', async (event) => {
      if (event.session !== session || signal?.aborted) return;
      const photo = itemsByKey.get(event.key);
      if (!photo) return;

      let uri: string | null = null;
      let unavailable = false;
      try {
        uri = loadPhoto ? await loadPhoto(photo, { retry: event.retry }) : (photo.uri ?? null);
        unavailable = uri === null;
      } catch {
        // A rejected load is retryable.
      }

      if (activeSession === session && !signal?.aborted) {
        await viewer.setPhoto(session, event.key, uri, unavailable).catch(() => {});
      }
    })
  );
  signal?.addEventListener('abort', abort);

  presented = await viewer
    .present(session, items, initialIndex, caption ?? null, labels)
    .catch(() => false);
  if (!presented) release();
  else if (signal?.aborted) abort();
  return presented;
}
