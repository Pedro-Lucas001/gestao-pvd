/** @type {import('tailwindcss').Config} */
export default {
    content: ["./index.html", "./src/**/*.{js,jsx}"],
    theme: {
      extend: {
        colors: {
          dark: {
            900: '#0F1115',
            800: '#1A1D24',
            700: '#2A2F3A',
          },
          brasa: {
            500: '#FF5722',
            600: '#E64A19',
            glow: 'rgba(255, 87, 34, 0.4)'
          }
        },
        fontFamily: {
          sans: ['"Inter"', '"Space Grotesk"', 'sans-serif'],
        },
        boxShadow: {
          'brasa-glow': '0 4px 20px -2px rgba(255, 87, 34, 0.4)',
          'glass': '0 8px 32px 0 rgba(0, 0, 0, 0.37)',
        }
      },
    },
    plugins: [],
  }