import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  plugins: [
    tailwindcss(), 
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      // Faz cache de todos os ficheiros estáticos para funcionar offline
      workbox: {
        globPatterns: ['**/*.{js,css,html,ico,png,svg}']
      },
      manifest: {
        name: 'Planeta Lanches Enterprise',
        short_name: 'PlanetaPDV',
        description: 'Sistema Integrado de Gestão e KDS',
        theme_color: '#0F1115', // Ultra Dark
        background_color: '#0F1115',
        display: 'standalone',
        icons: [
          {
            src: '/brand/favicon.svg',
            sizes: '192x192',
            type: 'image/svg+xml'
          },
          {
            src: '/brand/planeta-art.png',
            sizes: '512x512',
            type: 'image/png'
          }
        ]
      }
    })
  ]
});