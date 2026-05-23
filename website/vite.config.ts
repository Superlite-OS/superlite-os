import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  base: '/superlite-os/',
  plugins: [react()],
  build: {
    outDir: 'dist',
  },
});
