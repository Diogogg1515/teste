import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { getCurrentUser } from "@/lib/auth/get-user";

export async function NotificationsBadge() {
  const user = await getCurrentUser();
  if (!user) return null;

  const supabase = await createClient();
  const { count } = await supabase
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .is("read_at", null);

  if (!count || count === 0) {
    return (
      <Link
        href="/notificacoes"
        className="text-center text-sm underline"
      >
        Notificações
      </Link>
    );
  }

  return (
    <Link
      href="/notificacoes"
      className="flex items-center justify-center gap-2 text-center text-sm underline"
    >
      Notificações
      <span className="rounded-full bg-red-600 px-2 py-0.5 text-xs font-semibold text-white">
        {count}
      </span>
    </Link>
  );
}
