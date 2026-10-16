import { createClient } from "@/lib/supabase/server";

export type ClientSummary = {
  id: string;
  name: string;
  servicesCount: number;
  lastServiceAt: string | null;
};

// Clientes do trabalhador (baseado em serviços onde ele é o worker_id).
export async function listMyClients(): Promise<ClientSummary[]> {
  const supabase = await createClient();

  // Busca serviços onde o usuário é worker, agrupa por cliente
  const { data, error } = await supabase
    .from("services")
    .select(
      `
      client_id,
      created_at,
      client:client_id(name)
    `
    )
    .order("created_at", { ascending: false });

  if (error || !data) {
    console.error("Erro ao listar clientes:", error?.code);
    return [];
  }

  type ServiceRow = {
    client_id: string;
    created_at: string;
    client: { name: string }[] | null;
  };

  // Agrupa por cliente
  const clientMap = new Map<string, { name: string; count: number; lastAt: string }>();

  data.forEach((row: ServiceRow) => {
    const clientId = row.client_id;
    const clientName = row.client?.[0]?.name ?? "Cliente";
    const createdAt = row.created_at;

    const existing = clientMap.get(clientId);
    if (existing) {
      existing.count++;
      if (createdAt > existing.lastAt) {
        existing.lastAt = createdAt;
      }
    } else {
      clientMap.set(clientId, {
        name: clientName,
        count: 1,
        lastAt: createdAt,
      });
    }
  });

  // Converte para array e ordena por último serviço
  return Array.from(clientMap.entries())
    .map(([id, data]) => ({
      id,
      name: data.name,
      servicesCount: data.count,
      lastServiceAt: data.lastAt,
    }))
    .sort((a, b) => {
      if (!a.lastServiceAt) return 1;
      if (!b.lastServiceAt) return -1;
      return b.lastServiceAt.localeCompare(a.lastServiceAt);
    })
    .slice(0, 20);
}
