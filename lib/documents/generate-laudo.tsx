import { renderToBuffer } from "@react-pdf/renderer";
import { LaudoPDF } from "./laudo-template";
import { createClient } from "@/lib/supabase/server";

type LaudoData = {
  serviceNumber: number;
  serviceType: string;
  address: string;
  createdAt: string;
  completedAt: string | null;
  clientName: string;
  workerName: string;
  records: Array<{
    authorRole: "client" | "worker";
    content: string;
    createdAt: string;
  }>;
};

// Busca dados do serviço para o laudo
async function fetchServiceData(serviceId: string): Promise<LaudoData | null> {
  const supabase = await createClient();

  // Busca serviço
  const { data: service, error: serviceError } = await supabase
    .from("services")
    .select(
      `
      service_number,
      service_type,
      service_address,
      created_at,
      completed_at,
      client:client_id(name),
      worker:worker_id(name)
    `
    )
    .eq("id", serviceId)
    .single();

  if (serviceError || !service) {
    console.error("Erro ao buscar serviço:", serviceError?.code);
    return null;
  }

  // Busca registros
  const { data: records, error: recordsError } = await supabase
    .from("service_records")
    .select("author_role, content, created_at")
    .eq("service_id", serviceId)
    .order("created_at", { ascending: true });

  if (recordsError) {
    console.error("Erro ao buscar registros:", recordsError.code);
    return null;
  }

  return {
    serviceNumber: service.service_number,
    serviceType: service.service_type,
    address: service.service_address,
    createdAt: service.created_at,
    completedAt: service.completed_at,
    clientName: service.client?.[0]?.name ?? "Cliente",
    workerName: service.worker?.[0]?.name ?? "Trabalhador",
    records: (records ?? []).map((r) => ({
      authorRole: r.author_role as "client" | "worker",
      content: r.content,
      createdAt: r.created_at,
    })),
  };
}

// Gera PDF e salva no Storage
export async function generateLaudo(
  serviceId: string
): Promise<{ success: boolean; documentId?: string; error?: string }> {
  try {
    // Busca dados
    const data = await fetchServiceData(serviceId);
    if (!data) {
      return { success: false, error: "Serviço não encontrado." };
    }

    // Gera PDF
    const pdfBuffer = await renderToBuffer(<LaudoPDF data={data} />);

    // Salva no Storage
    const supabase = await createClient();
    const fileName = `${serviceId}/laudo-${Date.now()}.pdf`;

    const { error: uploadError } = await supabase.storage
      .from("service-files")
      .upload(fileName, pdfBuffer, {
        contentType: "application/pdf",
        upsert: false,
      });

    if (uploadError) {
      console.error("Erro ao fazer upload do laudo:", uploadError);
      return { success: false, error: "Erro ao salvar laudo." };
    }

    // Registra documento na tabela
    const { data: docData, error: docError } = await supabase
      .from("service_documents")
      .insert({
        service_id: serviceId,
        document_type: "laudo",
        storage_path: fileName,
        generated_by: (await supabase.auth.getUser()).data.user?.id,
      })
      .select("id")
      .single();

    if (docError || !docData) {
      console.error("Erro ao registrar documento:", docError?.code);
      return { success: false, error: "Erro ao registrar documento." };
    }

    return { success: true, documentId: docData.id };
  } catch (error) {
    console.error("Erro ao gerar laudo:", error);
    return { success: false, error: "Erro inesperado ao gerar laudo." };
  }
}
