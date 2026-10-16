"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type UpdateState = { error: string | null };

export async function updatePassword(
  _prevState: UpdateState,
  formData: FormData,
): Promise<UpdateState> {
  const password = String(formData.get("password") ?? "");
  const confirm = String(formData.get("confirm") ?? "");

  if (password.length < 8) {
    return { error: "A senha deve ter pelo menos 8 caracteres." };
  }
  if (password !== confirm) {
    return { error: "As senhas não conferem." };
  }

  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  if (!data?.claims) {
    return { error: "Sua sessão expirou. Peça um novo link de recuperação." };
  }

  const { error } = await supabase.auth.updateUser({ password });
  if (error) {
    console.error("Erro ao atualizar senha:", error.code);
    return {
      error: "Não foi possível atualizar a senha. Peça um novo link e tente de novo.",
    };
  }

  redirect("/painel");
}