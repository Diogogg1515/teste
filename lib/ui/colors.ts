// Guia de cores com contraste WCAG AA (4.5:1 texto, 3:1 UI)

export const colors = {
  // Primárias (botões ação)
  primary: {
    bg: "bg-blue-600 hover:bg-blue-700", // Contraste 4.5:1+ com branco
    text: "text-blue-600",
    border: "border-blue-600",
  },

  // Sucesso
  success: {
    bg: "bg-green-600 hover:bg-green-700",
    text: "text-green-700", // Mais escuro para contraste
    bgLight: "bg-green-50",
    textOnLight: "text-green-900",
  },

  // Erro
  error: {
    bg: "bg-red-600 hover:bg-red-700",
    text: "text-red-700",
    bgLight: "bg-red-50",
    textOnLight: "text-red-900",
  },

  // Alerta
  warning: {
    bg: "bg-orange-600 hover:bg-orange-700",
    text: "text-orange-700",
    bgLight: "bg-orange-50",
    textOnLight: "text-orange-900",
  },

  // Neutro (secundário)
  secondary: {
    bg: "bg-gray-900 hover:bg-gray-800",
    bgLight: "bg-gray-50 hover:bg-gray-100",
    text: "text-gray-900", // Preto quase puro = contraste máximo
    textMuted: "text-gray-600", // 4.5:1+ em branco
    border: "border-gray-300",
  },

  // WhatsApp
  whatsapp: {
    bg: "bg-green-600 hover:bg-green-700",
  },
} as const;

// Uso:
// <button className={colors.primary.bg}>Ação Principal</button>
// <p className={colors.secondary.textMuted}>Texto secundário</p>
