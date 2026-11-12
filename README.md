# Expo Photo Viewer

A fullscreen UIKit photo gallery for Expo. Tap a thumbnail to zoom into the gallery, swipe to page through photos, pinch to zoom, and drag down to return to the thumbnail.

- Opens at any photo in a gallery.
- Uses the full screen while preserving each photo's aspect ratio.
- Lets you pan a zoomed photo and resume paging after zooming out.
- Waits for the opening transition to finish before accepting a downward dismissal.
- Supports a local preview while the app loads the full-resolution photo.

## Compatibility

| Environment | Support |
| --- | --- |
| iOS 18+ | Supported in an Expo development or production build |
| iOS 17 and earlier | Use your app's fallback |
| Android and web | Use your app's fallback. Android support is outside the scope of this release |
| Expo Go | Use a development build with the native module linked |

This release targets Expo SDK 58 and React Native 0.88. No config plugin or photo library permission is required. UIKit uses a fade when Reduce Motion is enabled or a source thumbnail is missing at launch. The close button is available in that case.

## Install

Install the package from the [GitHub release](https://github.com/SoaringLabs/expo-photo-viewer/releases/tag/v0.2.0), then rebuild your iOS app.

```sh
npx expo install https://github.com/SoaringLabs/expo-photo-viewer/releases/download/v0.2.0/expo-photo-viewer-0.2.0.tgz
npx expo run:ios
```

When upgrading from 0.1.0, remove the `caption` option from your calls and rebuild the iOS app.

## Quick start

The viewer accepts local `file://` URLs. For bundled images, use [Expo Asset](https://docs.expo.dev/versions/v58.0.0/sdk/asset/) to download the asset locally and pass its `localUri`. For a remote or authenticated photo, download it to a local file in your app and pass the URI directly or through `loadPhoto`.

Keep each source thumbnail mounted while the gallery is open. Use `collapsable={false}` on its wrapper so the native transition can find it. Pass each thumbnail's ref in a multi-photo gallery so dismissal can return to the current photo.

```tsx
import { useRef, type ComponentRef } from 'react';
import { Image, Pressable, View } from 'react-native';
import { openPhotoViewer } from 'expo-photo-viewer';

export function PhotoThumbnail({ uri }: { uri: string }) {
  const source = useRef<ComponentRef<typeof View>>(null);

  return (
    <Pressable
      accessibilityLabel="View photo"
      accessibilityRole="button"
      onPress={async () => {
        const opened = await openPhotoViewer({
          photos: [{ key: 'photo-1', uri, source: source.current }],
        });
        if (!opened) {
          // Open your app's fallback viewer if available.
        }
      }}>
      <View ref={source} collapsable={false}>
        <Image source={{ uri }} style={{ width: 120, height: 120 }} />
      </View>
    </Pressable>
  );
}
```

## API

`isPhotoViewerSupported(): boolean` checks the OS and whether the native module is linked.

`openPhotoViewer(options): Promise<boolean>` presents one gallery and resolves once presentation starts. It returns `false` if the viewer cannot open, for example on an unsupported platform or when a gallery is already open.

| Option | Description |
| --- | --- |
| `photos` | Array of photos with unique `key` values. Each can include a full-size `uri`, a temporary `previewUri`, `width` and `height` for the initial aspect ratio, and a native thumbnail `source` |
| `initialIndex` | Zero-based starting photo index. Defaults to `0` |
| `labels` | Optional strings for `close`, `retry`, `unavailable`, and `position`. The position template accepts `{current}` and `{total}` |
| `closeButton` | Optional appearance overrides for the close button. The standard UIKit close button is the default |
| `loadPhoto(photo, { retry })` | Async loader for a missing or failed full-size photo. Return a local URI on success or `null` if unavailable. Throw to let the viewer offer a retry |
| `onClose` | Called when the native gallery closes |
| `signal` | Optional `AbortSignal` that closes the gallery and discards results from pending loads. The loader can use the same signal to cancel its own work |

The viewer reads local files. The caller controls network requests, authentication, and file lifetime.

### Close button

Omit `closeButton` to use UIKit's system appearance. On iOS 26 and later it uses Liquid Glass, and on earlier supported versions it uses UIKit's standard close button. Set `closeButton` to customize the SF Symbol, tint, or background. Use `labels.close` to customize the VoiceOver label.

```ts
await openPhotoViewer({
  photos,
  closeButton: {
    symbolName: 'chevron.down',
    tintColor: '#fff',
    backgroundColor: '#315f4b',
  },
});
```

Rebuild your iOS app after updating the native module to use the appearance options.

## Run the example

The [example app](./example) opens a three-photo gallery from bundled images of different aspect ratios.

The sample photos are available under the [Unsplash License](https://unsplash.com/license). Photos by [Sergei Gussev](https://unsplash.com/photos/rocky-coastline-with-ocean-waves-at-sunset-aY29FSy6R8k), [Hameen Reynolds](https://unsplash.com/photos/aerial-view-of-waves-crashing-on-a-sandy-beach-zWFa7mlQAYk), and [Howard Walsh](https://unsplash.com/photos/rocky-coastline-with-cliffs-and-the-ocean-vnZWPkhFtQ8).

```sh
corepack enable
pnpm install --frozen-lockfile
pnpm run example:ios
```

Run `pnpm run build`, `pnpm run lint`, and `pnpm --filter expo-photo-viewer-example typecheck` before submitting a change. When changing gestures, check an immediate left swipe after opening, a short downward drag that cancels, a completed downward drag, and paging after zooming back out.

## License

[MIT](./LICENSE)
