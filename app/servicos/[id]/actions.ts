"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requireRole } from "@/lib/auth/require-role";
import { isUuid } from "@/lib/utils/uuid";
import { ALL_STATUSES } from "@/lib/services/status";

export type RecordFormState = { error: string | null; savedAt: number | null };

// Mesmas regras do bucket "service-files" (o Storage também confere).
const PHOTO_EXTENSIONS: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};
const MAX_PHOTO_BYTES = 10 * 1024 * 1024; // 10 MB

// Quem decide de verdade é o banco: só participantes criam registros,
// cada um com o próprio papel, e só enquanto o serviço permite.
export async function addRecord(
  _prevState: RecordFormState,
  formData: FormData,
): Promise<RecordFormState> {
  const serviceId = String(formData.get("service_id") ?? "");
  const content = String(formData.get("content") ?? "").trim();
  const caption = String(formData.get("caption") ?? "").trim().slice(0, 300);

  if (!isUuid(serviceId)) {
    return { error: "Serviço inválido.", savedAt: null };
  }
  if (content.length < 1 || content.length > 5000) {
    return {
      error: "Escreva o registro (até 5000 caracteres).",
      savedAt: null,
    };
  }

  const user = await requireRole(["client", "worker"]);
  const role = user.profile.role;

  const supabase = await createClient();

  // Foto (opcional). Quando nenhuma foto é escolhida, o navegador pode mandar
  // um arquivo vazio (size === 0) ou nem incluir o campo. Ignoramos ambos.
  const entry = formData.get("file");
  const file = entry instanceof File && entry.size > 0 ? entry : null;

  let filePath: string | null = null;
  let fileMeta: { name: string; type: string; size: number } | null = null;

  if (file) {
    const extension = PHOTO_EXTENSIONS[file.type];
    if (!extension) {
      return {
        error: "Formato de foto não aceito. Use JPG, PNG ou WEBP.",
        savedAt: null,
      };
    }
    if (file.size > MAX_PHOTO_BYTES) {
      return {
        error: "A foto é muito grande. O máximo é 10 MB.",
        savedAt: null,
      };
    }

    // A primeira pasta precisa ser o ID do serviço (regra do Storage).
    const path = `${serviceId}/${crypto.randomUUID()}.${extension}`;
    const { error: uploadError } = await supabase.storage
      .from("service-files")
      .upload(path, file, { contentType: file.type, upsert: false });

    if (uploadError) {
      console.error("Erro ao enviar a foto:", uploadError.message);
      return {
        error:
          "Não foi possível enviar a foto. Confira se o serviço aceita novos registros e tente de novo.",
        savedAt: null,
      };
    }
    filePath = path;
    fileMeta = { name: file.name, type: file.type, size: file.size };
  }

  // 1. Cria o registro PRIMEIRO (garante que texto sempre salva, mesmo sem foto)
  const { data: recordData, error: recordError } = await supabase
    .from("service_records")
    .insert({
      service_id: serviceId,
      author_id: user.id,
      author_role: role,
      content,
    })
    .select("id")
    .single();

  if (recordError || !recordData) {
    console.error("Erro ao salvar registro:", recordError?.code);
    // Se upload deu certo mas registro falhou, tenta limpar o Storage
    if (filePath) {
      await supabase.storage.from("service-files").remove([filePath]).catch(() => {});
    }
    return {
      error:
        "Não foi possível salvar o registro. Confira se o serviço aceita novos registros e tente de novo.",
      savedAt: null,
    };
  }

  const recordId = recordData.id;

  // 2. Se houve foto, cria registro em service_files vinculado ao record
  if (filePath && fileMeta) {
    const { error: fileRecordError } = await supabase.from("service_files").insert({
      service_id: serviceId,
      record_id: recordId,
      uploaded_by: user.id,
      file_type: "photo",
      storage_path: filePath,
      original_name: fileMeta.name.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 120),
      mime_type: fileMeta.type,
      file_size: fileMeta.size,
      caption: caption || null,
    });

    if (fileRecordError) {
      console.error("Erro ao registrar a foto:", fileRecordError.code, fileRecordError.message);
      // Foto subiu, registro criado, mas link falhou. Foto órfã será limpa pelo job de retenção.
      revalidatePath(`/servicos/${serviceId}`);
      return {
        error:
          "O registro foi salvo, mas a foto não pôde ser anexada. Tente enviar a foto em um novo registro.",
        savedAt: Date.now(),
      };
    }
  }

  // 3. Notificar a outra parte do serviço
  const { data: serviceData } = await supabase
    .from("services")
    .select("client_id, worker_id")
    .eq("id", serviceId)
    .single();

  if (serviceData) {
    const recipientId = role === "client" ? serviceData.worker_id : serviceData.client_id;
    const authorLabel = role === "client" ? "cliente" : "trabalhador";

    await supabase.from("notifications").insert({
      user_id: recipientId,
      type: "new_record",
      title: "Novo registro no serviço",
      message: `O ${authorLabel} adicionou um novo registro.`,
      resource_type: "service",
      resource_id: serviceId,
    });
  }

  revalidatePath(`/servicos/${serviceId}`);
  return { error: null, savedAt: Date.now() };
}

// Mudança de status (só o profissional dono do serviço, e só transições
// válidas: o banco confere tudo).
export async function changeStatus(formData: FormData): Promise<void> {
  const id = String(formData.get("service_id") ?? "");
  const status = String(formData.get("status") ?? "");

  if (!isUuid(id) || !(ALL_STATUSES as string[]).includes(status)) {
    return;
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("change_service_status", {
    p_service_id: id,
    p_new_status: status,
  });

  if (error) {
    console.error("Erro ao mudar status:", error.message);
    redirect(`/servicos/${id}?erro=status`);
  }

  revalidatePath(`/servicos/${id}`);
  revalidatePath("/painel");
}