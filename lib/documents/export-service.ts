import { createClient } from "@/lib/supabase/server";

type ServiceRow = {
  service_number: number;
  service_type: string;
  service_address: string;
  status: string;
  created_at: string;
  completed_at: string | null;
  expires_at: string;
  client_id: string | null;
  worker_id: string | null;
  client: { name: string; id: string }[] | null;
  worker: { name: string; id: string }[] | null;
};

type RecordRow = {
  author_role: "client" | "worker";
  content: string;
  created_at: string;
  files: Array<{
    original_name: string;
    file_size: number;
    caption: string | null;
  }> | null;
};

type ServiceExport = {
  service: {
    number: number;
    type: string;
    address: string;
    status: string;
    createdAt: string;
    completedAt: string | null;
    expiresAt: string;
  };
  participants: {
    client: string;
    worker: string;
  };
  records: Array<{
    author: "Cliente" | "Trabalhador";
    content: string;
    createdAt: string;
    files: Array<{
      name: string;
      size: number;
      caption: string;
    }>;
  }>;
  metadata: {
    exportedAt: string;
    exportedBy: "Cliente" | "Trabalhador";
  };
};

// Busca todos dados do serviço para export
export async function exportServiceData(
  serviceId: string
): Promise<ServiceExport | null> {
  const supabase = await createClient();

  // Busca serviço (RLS já garante participação)
  const { data: service, error: serviceError } = await supabase
    .from("services")
    .select(
      `
      service_number,
      service_type,
      service_address,
      status,
      created_at,
      completed_at,
      expires_at,
      client_id,
      worker_id,
      client:client_id(name, id),
      worker:worker_id(name, id)
    `
    )
    .eq("id", serviceId)
    .single();

  if (serviceError || !service) {
    console.error("Erro ao buscar serviço:", serviceError?.code);
    return null;
  }

  // Busca registros com arquivos
  const { data: records, error: recordsError } = await supabase
    .from("service_records")
    .select(
      `
      author_role,
      content,
      created_at,
      files:service_files(original_name, file_size, caption)
    `
    )
    .eq("service_id", serviceId)
    .order("created_at", { ascending: true });

  if (recordsError) {
    console.error("Erro ao buscar registros:", recordsError.code);
    return null;
  }

  // Quem está exportando
  const { data: userData } = await supabase.auth.getUser();
  const serviceTyped = service as ServiceRow;
  const userRole =
    serviceTyped.client_id === userData?.user?.id ? "Cliente" : "Trabalhador";

  return {
    service: {
      number: serviceTyped.service_number,
      type: serviceTyped.service_type,
      address: serviceTyped.service_address,
      status: serviceTyped.status,
      createdAt: serviceTyped.created_at,
      completedAt: serviceTyped.completed_at,
      expiresAt: serviceTyped.expires_at,
    },
    participants: {
      client: serviceTyped.client?.[0]?.name ?? "Cliente",
      worker: serviceTyped.worker?.[0]?.name ?? "Trabalhador",
    },
    records: (records ?? []).map((r: RecordRow) => ({
      author: r.author_role === "client" ? "Cliente" : "Trabalhador",
      content: r.content,
      createdAt: r.created_at,
      files: (r.files ?? []).map((f) => ({
        name: f.original_name,
        size: f.file_size,
        caption: f.caption ?? "",
      })),
    })),
    metadata: {
      exportedAt: new Date().toISOString(),
      exportedBy: userRole,
    },
  };
}

// Formata como texto legível
export function formatServiceExport(data: ServiceExport): string {
  const lines: string[] = [];

  lines.push("═══════════════════════════════════════════════════");
  lines.push(`INFORMAÇÕES DO SERVIÇO #${String(data.service.number).padStart(3, "0")}`);
  lines.push("═══════════════════════════════════════════════════");
  lines.push("");

  lines.push("IDENTIFICAÇÃO");
  lines.push("-".repeat(50));
  lines.push(`Tipo: ${data.service.type}`);
  lines.push(`Endereço: ${data.service.address}`);
  lines.push(`Status: ${data.service.status}`);
  lines.push(`Criado em: ${new Date(data.service.createdAt).toLocaleString("pt-BR")}`);
  if (data.service.completedAt) {
    lines.push(
      `Concluído em: ${new Date(data.service.completedAt).toLocaleString("pt-BR")}`
    );
  }
  lines.push(
    `Expira em: ${new Date(data.service.expiresAt).toLocaleString("pt-BR")}`
  );
  lines.push("");

  lines.push("PARTICIPANTES");
  lines.push("-".repeat(50));
  lines.push(`Cliente: ${data.participants.client}`);
  lines.push(`Trabalhador: ${data.participants.worker}`);
  lines.push("");

  lines.push("REGISTROS");
  lines.push("-".repeat(50));
  if (data.records.length === 0) {
    lines.push("Nenhum registro.");
  } else {
    data.records.forEach((record, index) => {
      lines.push("");
      lines.push(`[${index + 1}] ${record.author}`);
      lines.push(`Data: ${new Date(record.createdAt).toLocaleString("pt-BR")}`);
      lines.push("");
      lines.push(record.content);

      if (record.files.length > 0) {
        lines.push("");
        lines.push("Arquivos anexados:");
        record.files.forEach((file) => {
          lines.push(`  - ${file.name} (${Math.round(file.size / 1024)} KB)`);
          if (file.caption) {
            lines.push(`    Legenda: ${file.caption}`);
          }
        });
      }
      lines.push("-".repeat(50));
    });
  }

  lines.push("");
  lines.push("METADADOS");
  lines.push("-".repeat(50));
  lines.push(
    `Exportado em: ${new Date(data.metadata.exportedAt).toLocaleString("pt-BR")}`
  );
  lines.push(`Exportado por: ${data.metadata.exportedBy}`);
  lines.push("");
  lines.push("═══════════════════════════════════════════════════");
  lines.push("Documento gerado automaticamente pelo souza.l");
  lines.push("As informações foram registradas pelas partes durante");
  lines.push("a execução do serviço.");
  lines.push("═══════════════════════════════════════════════════");

  return lines.join("\n");
}
