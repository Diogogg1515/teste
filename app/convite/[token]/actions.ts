"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { TOKEN_PATTERN } from "@/lib/invites/invites";
import { isUuid } from "@/lib/utils/form";

export type AcceptState = { error: string | null };

const MESSAGES: Record<string, string> = {
  invalid_address: "Informe o endereço do serviço (entre 5 e 300 caracteres).",
  invite_expired: "Este convite expirou. Peça um novo ao profissional.",
  invite_already_used: "Este convite já foi usado.",
  invite_cancelled: "Este convite foi cancelado pelo profissional.",
  invite_not_found: "Convite não encontrado. Confira o link.",
  not_allowed: "Só contas de cliente podem aceitar convites.",
};

function friendlyMessage(raw: string): string {
  const key = Object.keys(MESSAGES).find((code) => raw.includes(code));
  return key
    ? MESSAGES[key]
    : "Não foi possível aceitar o convite. Tente novamente.";
}

// Quem decide de verdade é o banco: confere o convite, o papel de cliente
// e cria o serviço de uma vez só.
export async function acceptInvite(
  _prevState: AcceptState,
  formData: FormData,
): Promise<AcceptState> {
  const token = String(formData.get("token") ?? "");
  const address = String(formData.get("address") ?? "").trim();

  if (!TOKEN_PATTERN.test(token)) {
    return { error: MESSAGES.invite_not_found };
  }
  if (address.length < 5 || address.length > 300) {
    return { error: MESSAGES.invalid_address };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("redeem_service_invite", {
    p_token: token,
    p_address: address,
  });

  if (error) {
    // Registra só o motivo (sem o código do convite).
    console.error("Erro ao aceitar convite:", error.message);
    return { error: friendlyMessage(error.message) };
  }

  const serviceId = String(data ?? "");
  redirect(isUuid(serviceId) ? `/servicos/${serviceId}?novo=1` : "/painel?aceito=1");
}
