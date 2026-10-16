import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  experimental: {
    serverActions: {
      // O padrão é 1 MB, e foto de celular passa disso. O formulário reduz a
      // foto antes de enviar (cerca de 1 MB ou menos), e este limite dá folga.
      bodySizeLimit: "4mb",
    },
  },
};

export default nextConfig;