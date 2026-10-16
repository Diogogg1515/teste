import { createClient } from "@/lib/supabase/server";

export type ServiceDocument = {
  id: string;
  documentType: string;
  storagePath: string;
  createdAt: string;
};

// Lista documentos do serviço (laudos)
export async function listServiceDocuments(serviceId: string): Promise<ServiceDocument[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("service_documents")
    .select("id, document_type, storage_path, created_at")
    .eq("service_id", serviceId)
    .order("created_at", { ascending: false });

  if (error || !data) {
    console.error("Erro ao listar documentos:", error?.code);
    return [];
  }

  return data.map((row) => ({
    id: row.id,
    documentType: row.document_type,
    storagePath: row.storage_path,
    createdAt: row.created_at,
  }));
}
