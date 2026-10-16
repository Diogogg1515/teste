import { createClient } from "@/lib/supabase/server";

// Conta notificações não lidas do usuário atual.
export async function countUnreadNotifications(): Promise<number> {
  const supabase = await createClient();
  const { count, error } = await supabase
    .from("notifications")
    .select("*", { count: "exact", head: true })
    .is("read_at", null);

  if (error) {
    console.error("Erro ao contar notificações:", error.code);
    return 0;
  }

  return count ?? 0;
}
