// V1: dados do único trabalhador, hardcoded.
// Migrar para tabela worker_profiles quando houver múltiplos profissionais.

export const WORKER_INFO = {
  name: "José Souza",
  profession: "Encanador",
  region: "São Paulo, SP",
  description:
    "Profissional autônomo com experiência em instalações hidráulicas, manutenção e reparos. Atendimento residencial e comercial.",
  phone: "11999999999", // Número real do trabalhador
  whatsapp: "5511999999999", // Formato internacional
  services: [
    "Instalação hidráulica",
    "Reparos de vazamentos",
    "Troca de torneiras e registros",
    "Desentupimento",
    "Manutenção preventiva",
    "Instalação de aquecedores",
  ],
  workSamples: [
    {
      title: "Instalação completa",
      description: "Sistema hidráulico residencial",
      imageUrl: "/trabalhos/sample-1.jpg", // placeholder: adicionar fotos reais depois
    },
    {
      title: "Reparo de vazamento",
      description: "Correção de tubulação",
      imageUrl: "/trabalhos/sample-2.jpg",
    },
    {
      title: "Troca de registros",
      description: "Modernização do sistema",
      imageUrl: "/trabalhos/sample-3.jpg",
    },
  ],
  about: `Com mais de 15 anos de experiência, realizo serviços hidráulicos com qualidade e compromisso.
Cada trabalho é documentado e registrado para sua segurança e transparência.`,
} as const;
