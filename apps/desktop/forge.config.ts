import { fileURLToPath } from 'node:url'

const fromDesktopRoot = (path: string) => fileURLToPath(new URL(path, import.meta.url))

export default {
  makers: [
    {
      name: '@electron-forge/maker-zip',
      platforms: ['darwin'],
    },
  ],
  packagerConfig: {
    appBundleId: 'dev.keepling.desktop',
    appCategoryType: 'public.app-category.productivity',
    appCopyright: 'Copyright © Keepling contributors',
    asar: true,
    extraResource: [
      fromDesktopRoot('./dist/main'),
      fromDesktopRoot('./dist/preload'),
      fromDesktopRoot('./dist/renderer'),
      fromDesktopRoot('./dist/worker'),
      fromDesktopRoot('./migrations'),
      fromDesktopRoot('./assets'),
    ],
    ignore: [/node_modules/],
    name: 'Keepling',
    prune: false,
  },
  plugins: [],
}
