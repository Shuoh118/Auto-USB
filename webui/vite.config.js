import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { viteSingleFile } from 'vite-plugin-singlefile'

// The WebUI is shipped as one self-contained index.html: managers load it
// from file:// or a loopback server, so a single inline bundle avoids every
// CORS / missing-asset failure mode on old WebViews.
export default defineConfig({
  plugins: [vue(), viteSingleFile()],
  base: './',
  build: {
    outDir: '../webroot',
    emptyOutDir: true,
    target: 'es2019',
    cssCodeSplit: false,
    assetsInlineLimit: 1024 * 1024,
  },
})
