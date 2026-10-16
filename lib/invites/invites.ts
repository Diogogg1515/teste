import { createClient } from "@/lib/supabase/server";

// O código do convite tem sempre 64 caracteres hexadecimais.
export const TOKEN_PATTERN = /^[0-9a-f]{64}$/;

export type InviteState = "valid" | "expired" | "accepted" | "cancelled";

export type InvitePreview = {
  workerName: string;
  serviceType: string;
  state: InviteState;
};

type PreviewRow = {
  o_worker_name: string;
  o_service_type: string;
  o_state: InviteState;
};

// Prévia liberada para visitantes: só nome do profissional e tipo do serviço.
export async function previewInvite(
  token: string,
): Promise<InvitePreview | null> {
  if (!TOKEN_PATTERN.test(token)) {
    return null;
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("preview_service_invite", {
    p_token: token,
  });

  if (error) {
    // Nunca registra o código do convite nos logs.
    console.error("Erro ao consultar convite:", error.code);
    return null;
  }

  const row = Array.isArray(data) ? (data[0] as PreviewRow | undefined) : undefined;
  if (!row) {
    return null;
  }

  return {
    workerName: row.o_worker_name,
    serviceType: row.o_service_type,
    state: row.o_state,
  };
}

export type InviteListItem = {
  id: string;
  serviceType: string;
  clientLabel: string;
  expiresAt: string;
  state: "pending" | "accepted" | "cancelled" | "expired";
};

type ListRow = {
  id: string;
  service_type: string;
  client_label: string;
  status: "pending" | "accepted" | "cancelled";
  expires_at: string;
};

// Convites do profissional logado (o banco só devolve os dele).
export async function listInvites(): Promise<InviteListItem[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("service_invites")
    .select("id, service_type, client_label, status, expires_at")
    .order("created_at", { ascending: false })
    .limit(50);

  if (error) {
    console.error("Erro ao listar convites:", error.code);
    return [];
  }

  const now = Date.now();
  return (data as ListRow[]).map((row) => ({
    id: row.id,
    serviceType: row.service_type,
    clientLabel: row.client_label,
    expiresAt: row.expires_at,
    state:
      row.status === "pending" && new Date(row.expires_at).getTime() <= now
        ? "expired"
        : row.status,
  }));
}
