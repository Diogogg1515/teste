import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const supabase = await createClient();
    const { id: fileId } = await params;

    // Verificar autenticação
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      return new NextResponse("Não autorizado", { status: 401 });
    }

    // Buscar o registro do arquivo e verificar se existe
    const { data: fileData, error: fileError } = await supabase
      .from("service_files")
      .select("storage_path, service_id")
      .eq("id", fileId)
      .single();

    if (fileError || !fileData) {
      return new NextResponse("Arquivo não encontrado", { status: 404 });
    }

    // Verificar se o usuário participa do serviço (autorização explícita)
    const { data: serviceData, error: serviceError } = await supabase
      .from("services")
      .select("client_id, worker_id")
      .eq("id", fileData.service_id)
      .single();

    if (serviceError || !serviceData) {
      return new NextResponse("Serviço não encontrado", { status: 404 });
    }

    // Confirmar que o usuário é participante
    if (serviceData.client_id !== user.id && serviceData.worker_id !== user.id) {
      return new NextResponse("Acesso negado", { status: 403 });
    }

    // Gerar URL assinada válida por 1 hora
    const { data: urlData } = await supabase.storage
      .from("service-files")
      .createSignedUrl(fileData.storage_path, 3600);

    if (urlData?.signedUrl) {
      // Redirecionar para a URL assinada do Storage
      return NextResponse.redirect(urlData.signedUrl);
    } else {
      return new NextResponse("Erro ao gerar URL do arquivo", { status: 500 });
    }
  } catch (error) {
    console.error("Erro ao servir arquivo:", error);
    return new NextResponse("Erro interno do servidor", { status: 500 });
  }
}