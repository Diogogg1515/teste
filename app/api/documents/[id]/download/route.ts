import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getCurrentUser } from "@/lib/auth/get-user";

type Context = {
  params: Promise<{ id: string }>;
};

export async function GET(request: Request, context: Context) {
  const user = await getCurrentUser();
  if (!user) {
    return NextResponse.json({ error: "Não autenticado" }, { status: 401 });
  }

  const { id } = await context.params;
  const supabase = await createClient();

  // Busca documento
  const { data: doc, error: docError } = await supabase
    .from("service_documents")
    .select("service_id, storage_path")
    .eq("id", id)
    .single();

  if (docError || !doc) {
    return NextResponse.json({ error: "Documento não encontrado" }, { status: 404 });
  }

  // Verifica permissão (usuário participa do serviço)
  const { data: service, error: serviceError } = await supabase
    .from("services")
    .select("client_id, worker_id")
    .eq("id", doc.service_id)
    .single();

  if (serviceError || !service) {
    return NextResponse.json({ error: "Serviço não encontrado" }, { status: 404 });
  }

  if (service.client_id !== user.id && service.worker_id !== user.id) {
    return NextResponse.json({ error: "Acesso negado" }, { status: 403 });
  }

  // Gera URL assinada (válida por 1 hora)
  const { data: signedData, error: signedError } = await supabase.storage
    .from("service-files")
    .createSignedUrl(doc.storage_path, 3600);

  if (signedError || !signedData?.signedUrl) {
    return NextResponse.json({ error: "Erro ao gerar link" }, { status: 500 });
  }

  // Redireciona para URL assinada
  return NextResponse.redirect(signedData.signedUrl);
}
