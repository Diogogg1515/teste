import { createClient } from "@/lib/supabase/server";

export type ServiceRequest = {
  id: string;
  serviceType: string;
  createdAt: string;
  workerName: string;
};

type RequestRow = {
  id: string;
  service_type: string;
  created_at: string;
  worker: { name: string }[] | null;
};

// Pedidos pendentes que o cliente recebeu (RLS já filtra pelo client_id).
export async function listPendingRequests(): Promise<ServiceRequest[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("service_requests")
    .select(
      `
      id,
      service_type,
      created_at,
      worker:worker_id(name)
    `
    )
    .eq("status", "pending")
    .order("created_at", { ascending: false })
    .limit(10);

  if (error || !data) {
    console.error("Erro ao listar pedidos:", error?.code);
    return [];
  }

  return data.map((row: RequestRow) => ({
    id: row.id,
    serviceType: row.service_type,
    createdAt: row.created_at,
    workerName: row.worker?.[0]?.name ?? "Profissional",
  }));
}
