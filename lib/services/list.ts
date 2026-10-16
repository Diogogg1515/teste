import { createClient } from "@/lib/supabase/server";

export type ServiceSummary = {
  id: string;
  number: number;
  serviceType: string;
  status: string;
  createdAt: string;
};

type Row = {
  id: string;
  service_number: number;
  service_type: string;
  status: string;
  created_at: string;
};

// Serviços do usuário logado (cliente ou profissional). O banco só devolve
// os serviços de que a pessoa participa.
export async function listMyServices(): Promise<ServiceSummary[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("services")
    .select("id, service_number, service_type, status, created_at")
    .order("created_at", { ascending: false })
    .limit(20);

  if (error || !data) {
    console.error("Erro ao listar serviços:", error?.code);
    return [];
  }

  return (data as Row[]).map((row) => ({
    id: row.id,
    number: row.service_number,
    serviceType: row.service_type,
    status: row.status,
    createdAt: row.created_at,
  }));
}
