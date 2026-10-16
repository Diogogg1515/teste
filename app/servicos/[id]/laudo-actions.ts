"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { generateLaudo } from "@/lib/documents/generate-laudo";
import { requireRole } from "@/lib/auth/require-role";

// Cliente solicita laudo
export async function requestLaudo(serviceId: string): Promise<void> {
  const user = await requireRole(["client"]);

  const supabase = await createClient();

  // Verifica se serviço está concluído
  const { data: service } = await supabase
    .from("services")
    .select("status, client_id, worker_id")
    .eq("id", serviceId)
    .single();

  if (!service || service.client_id !== user.id) return;
  if (service.status !== "completed") return;

  // Verifica se já existe solicitação pendente
  const { data: existingDoc } = await supabase
    .from("service_documents")
    .select("id")
    .eq("service_id", serviceId)
    .eq("document_type", "laudo")
    .maybeSingle();

  if (existingDoc) return;

  // Cria registro temporário (depois gera PDF)
  const { error: insertError } = await supabase.from("service_documents").insert({
    service_id: serviceId,
    document_type: "laudo_requested",
    storage_path: "",
  });

  if (insertError) {
    console.error("Erro ao registrar solicitação:", insertError);
    return;
  }

  // Notifica trabalhador
  await supabase.from("notifications").insert({
    user_id: service.worker_id,
    type: "laudo_requested",
    title: "Laudo solicitado",
    message: "O cliente solicitou o laudo do serviço.",
    resource_type: "service",
    resource_id: serviceId,
  });

  revalidatePath(`/servicos/${serviceId}`);
}

// Trabalhador gera laudo
export async function generateLaudoAction(serviceId: string): Promise<void> {
  const user = await requireRole(["worker"]);

  const supabase = await createClient();

  // Verifica propriedade
  const { data: service } = await supabase
    .from("services")
    .select("worker_id, client_id")
    .eq("id", serviceId)
    .single();

  if (!service || service.worker_id !== user.id) return;

  // Remove solicitação temporária
  await supabase
    .from("service_documents")
    .delete()
    .eq("service_id", serviceId)
    .eq("document_type", "laudo_requested");

  // Gera PDF
  const result = await generateLaudo(serviceId);
  if (!result.success) {
    console.error("Erro ao gerar laudo:", result.error);
    return;
  }

  // Notifica cliente
  await supabase.from("notifications").insert({
    user_id: service.client_id,
    type: "laudo_ready",
    title: "Laudo disponível",
    message: "O laudo do serviço está pronto para download.",
    resource_type: "service",
    resource_id: serviceId,
  });

  revalidatePath(`/servicos/${serviceId}`);
}
