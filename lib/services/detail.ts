import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/utils/form";
import type { ServiceStatus } from "@/lib/services/status";

export type ServiceDetail = {
  id: string;
  number: number;
  serviceType: string;
  address: string;
  status: ServiceStatus;
  createdAt: string;
  completedAt: string | null;
  expiresAt: string;
};

type ServiceRow = {
  id: string;
  service_number: number;
  service_type: string;
  service_address: string;
  status: ServiceStatus;
  created_at: string;
  completed_at: string | null;
  expires_at: string;
};

// O banco só devolve o serviço se a pessoa participa dele (RLS).
export async function getService(id: string): Promise<ServiceDetail | null> {
  if (!isUuid(id)) {
    return null;
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("services")
    .select(
      "id, service_number, service_type, service_address, status, created_at, completed_at, expires_at",
    )
    .eq("id", id)
    .maybeSingle();

  if (error) {
    console.error("Erro ao buscar serviço:", error.code);
    return null;
  }
  if (!data) {
    return null;
  }

  const row = data as ServiceRow;
  return {
    id: row.id,
    number: row.service_number,
    serviceType: row.service_type,
    address: row.service_address,
    status: row.status,
    createdAt: row.created_at,
    completedAt: row.completed_at,
    expiresAt: row.expires_at,
  };
}

export type ServiceFile = {
  id: string;
  originalName: string;
  mimeType: string;
  fileSize: number;
  caption: string;
  uploadUrl: string; // URL temporária assinada para download
};

export type ServiceRecord = {
  id: string;
  authorRole: "client" | "worker";
  content: string;
  createdAt: string;
  files: ServiceFile[];
};

type FileRow = {
  id: string;
  record_id: string;
  original_name: string;
  mime_type: string;
  file_size: number;
  storage_path: string;
  caption: string | null;
};

// Registros do serviço, do mais antigo para o mais novo.
export async function listRecords(serviceId: string): Promise<ServiceRecord[]> {
  const supabase = await createClient();
  const { data: recordsData, error: recordsError } = await supabase
    .from("service_records")
    .select("id, author_role, content, created_at")
    .eq("service_id", serviceId)
    .order("created_at", { ascending: true })
    .limit(500);

  if (recordsError || !recordsData || recordsData.length === 0) {
    if (recordsError) {
      console.error("Erro ao listar registros:", recordsError.code);
    }
    return [];
  }

  // Buscar arquivos anexados para todos os registros de uma vez
  const { data: filesData, error: filesError } = await supabase
    .from("service_files")
    .select("id, record_id, original_name, mime_type, file_size, storage_path, caption")
    .in(
      "record_id",
      recordsData.map((r) => r.id)
    );

  if (filesError) {
    console.error("Erro ao listar arquivos anexados:", filesError.code);
    // Continuamos mesmo se falhar ao buscar arquivos - os registros ainda são úteis
  }

  // Agrupar arquivos por record_id
  const filesByRecordId: Record<string, ServiceFile[]> = {};
  if (filesData) {
    filesData.forEach((file: FileRow) => {
      const recordId = file.record_id;
      if (!filesByRecordId[recordId]) {
        filesByRecordId[recordId] = [];
      }
      filesByRecordId[recordId].push({
        id: file.id,
        originalName: file.original_name,
        mimeType: file.mime_type,
        fileSize: file.file_size,
        caption: file.caption ?? "",
        uploadUrl: "",
      });
    });
  }

  return recordsData.map((row) => {
    const recordFiles = filesByRecordId[row.id] || [];

    return {
      id: row.id,
      authorRole: row.author_role,
      content: row.content,
      createdAt: row.created_at,
      files: recordFiles,
    };
  });
}

export type Counterpart = { name: string; role: "client" | "worker" };

type CounterpartRow = { o_name: string; o_role: "client" | "worker" };

// Nome da outra pessoa do serviço (cliente vê o profissional e vice-versa).
export async function getCounterpart(
  serviceId: string,
): Promise<Counterpart | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_service_counterpart", {
    p_service_id: serviceId,
  });

  if (error) {
    console.error("Erro ao buscar a outra parte do serviço:", error.code);
    return null;
  }

  const row = Array.isArray(data)
    ? (data[0] as CounterpartRow | undefined)
    : undefined;
  return row ? { name: row.o_name, role: row.o_role } : null;
}
