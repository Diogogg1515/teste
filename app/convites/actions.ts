"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { isUuid } from "@/lib/utils/form";

// Cancela um convite pendente. Quem confere o dono é o banco.
export async function cancelInvite(formData: FormData): Promise<void> {
  const id = String(formData.get("id") ?? "");
  if (!isUuid(id)) {
    return;
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_service_invite", {
    p_invite_id: id,
  });

  if (error) {
    console.error("Erro ao cancelar convite:", error.message);
  }

  revalidatePath("/convites");
}
