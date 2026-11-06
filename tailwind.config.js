// tailwind.config.js
module.exports = {
    content: ["./index.html", "./src/**/*.{js,jsx}"],
    theme: {
      extend: {
        colors: {
          dark: {
            900: '#0F1115', // Fundo principal (Ultra Dark)
            800: '#1A1D24', // Paineis e Cartões (Steel/Dark Grey)
            700: '#2A2F3A', // Bordas e Divisórias
          },
          brasa: {
            500: '#FF5722', // Laranja-fogo principal (Accent)
            600: '#E64A19', // Hover
            glow: 'rgba(255, 87, 34, 0.4)' // Sombra neon para realces
          }
        },
        fontFamily: {
          sans: ['"Inter"', '"Space Grotesk"', 'sans-serif'], // Tipografia geométrica
        },
        boxShadow: {
          'brasa-glow': '0 4px 20px -2px rgba(255, 87, 34, 0.4)',
          'glass': '0 8px 32px 0 rgba(0, 0, 0, 0.37)',
        }
      },
    },
    plugins: [],
  }