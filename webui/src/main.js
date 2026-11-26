import { createApp } from 'vue'
import 'miuix-vue/style.css'
import './styles.css'
import App from './App.vue'

// MMRL exposes window insets (status bar / gesture bar) through a local
// stylesheet; KernelSU and APatch rely on env(safe-area-inset-*).
if (typeof window !== 'undefined' && window.mmrl) {
  const link = document.createElement('link')
  link.rel = 'stylesheet'
  link.href = '/mmrl/insets.css'
  document.head.appendChild(link)
}

createApp(App).mount('#app')
