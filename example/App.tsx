import { Asset } from 'expo-asset';
import { isPhotoViewerSupported, openPhotoViewer } from 'expo-photo-viewer';
import { useEffect, useRef, useState, type ComponentRef } from 'react';
import { Image, Pressable, StyleSheet, Switch, Text, View } from 'react-native';

const samples = [
  { key: 'dusk', asset: require('./assets/dusk.jpg'), width: 1440, height: 960 },
  { key: 'dawn', asset: require('./assets/dawn.jpg'), width: 1080, height: 2348 },
  { key: 'mist', asset: require('./assets/mist.jpg'), width: 1200, height: 1200 },
  { key: 'white', asset: require('./assets/white.png'), width: 1206, height: 2622 },
];

export default function App() {
  const sources = useRef<Array<ComponentRef<typeof View> | null>>([]);
  const [assets, setAssets] = useState<Asset[]>([]);
  const [message, setMessage] = useState<string>();
  const [customClose, setCustomClose] = useState(false);
  const supported = isPhotoViewerSupported();

  useEffect(() => {
    let mounted = true;
    Asset.loadAsync(samples.map(({ asset }) => asset)).then(
      (images) => {
        if (mounted) setAssets(images);
      },
      () => {
        if (mounted) setMessage('The sample photos could not be loaded.');
      }
    );
    return () => {
      mounted = false;
    };
  }, []);

  async function open(initialIndex: number) {
    setMessage(undefined);
    const opened = await openPhotoViewer({
      photos: samples.map(({ key, width, height }, index) => ({
        key,
        width,
        height,
        uri: assets[index]?.localUri ?? undefined,
        source: sources.current[index],
      })),
      initialIndex,
      labels: { close: '关闭' },
      closeButton: customClose
        ? { symbolName: 'chevron.down', tintColor: '#fff', backgroundColor: '#315f4b' }
        : undefined,
    });
    if (!opened) setMessage('The gallery could not be opened.');
  }

  return (
    <View style={styles.screen}>
      <Text style={styles.title}>Photo Viewer</Text>
      <Text style={styles.description}>
        {supported ? 'Tap any photo to open the gallery.' : 'Use an iOS 18+ development build.'}
      </Text>
      <View style={styles.row}>
        {samples.map(({ key, asset }, index) => (
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={`Open photo ${index + 1}`}
            disabled={!supported || assets.length !== samples.length}
            key={key}
            style={styles.thumbnail}
            onPress={() => {
              void open(index);
            }}>
            <View
              ref={(view) => {
                sources.current[index] = view;
              }}
              collapsable={false}
              style={styles.thumbnail}>
              <Image source={asset} style={styles.photo} />
            </View>
          </Pressable>
        ))}
      </View>
      {supported && (
        <View style={styles.option}>
          <Text style={styles.description}>Custom close button</Text>
          <Switch
            accessibilityLabel="Custom close button"
            value={customClose}
            onValueChange={setCustomClose}
          />
        </View>
      )}
      {message && (
        <Text accessibilityRole="alert" style={styles.description}>
          {message}
        </Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, justifyContent: 'center', padding: 24, gap: 14, backgroundColor: '#111827' },
  title: { color: '#fff', fontSize: 32, fontWeight: '700' },
  description: { color: '#cbd5e1', fontSize: 16 },
  row: { flexDirection: 'row', gap: 8 },
  option: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  thumbnail: { flex: 1, aspectRatio: 1, borderRadius: 12, overflow: 'hidden' },
  photo: { width: '100%', height: '100%' },
});
