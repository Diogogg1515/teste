"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requireRole } from "@/lib/auth/require-role";

export async function markAsRead(notificationId: string) {
  const user = await requireRole(["client", "worker"]);
  const supabase = await createClient();

  // RLS garante que só pode atualizar suas próprias notificações
  const { error } = await supabase
    .from("notifications")
    .update({ read_at: new Date().toISOString() })
    .eq("id", notificationId)
    .eq("user_id", user.id);

  if (error) return { error: error.message };

  revalidatePath("/notificacoes");
  return { success: true };
}

export async function markAllAsRead(): Promise<void> {
  const user = await requireRole(["client", "worker"]);
  const supabase = await createClient();

  await supabase
    .from("notifications")
    .update({ read_at: new Date().toISOString() })
    .eq("user_id", user.id)
    .is("read_at", null);

  revalidatePath("/notificacoes");
}
