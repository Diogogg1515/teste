"use server";

import { createClient } from "@/lib/supabase/server";

export type ResetState = { error: string | null; info: string | null };

export async function requestPasswordReset(
  _prevState: ResetState,
  formData: FormData,
): Promise<ResetState> {
  const email = String(formData.get("email") ?? "").trim();

  if (!email) {
    return { error: "Informe seu e-mail.", info: null };
  }

  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL;
  if (!siteUrl) {
    throw new Error("Variável NEXT_PUBLIC_SITE_URL é obrigatória.");
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${siteUrl}/auth/callback?next=/atualizar-senha`,
  });

  if (error) {
    // Aparece só no terminal do servidor (ajuda a achar problemas de envio).
    console.error("Erro ao pedir recuperação de senha:", error.code);
  }

  // Resposta sempre igual: não revela se o e-mail tem cadastro.
  return {
    error: null,
    info: "Se existir uma conta com esse e-mail, enviamos um link para criar uma nova senha.",
  };
}