import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: {
    rolldownOptions: {
      output: {
        codeSplitting: {
          groups: [
            { name: "supabase-vendor", test: /node_modules\/@supabase\// },
            {
              name: "react-vendor",
              test:
                /node_modules\/(react|react-dom|scheduler|react-router|react-router-dom)\//,
            },
            { name: "qr-vendor", test: /node_modules\/qrcode.react\// },
          ],
        },
      },
    },
  },
});
