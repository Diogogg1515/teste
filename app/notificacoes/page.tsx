import { redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth/get-user";
import { createClient } from "@/lib/supabase/server";
import { formatDateTime } from "@/lib/services/format";
import { NotificationItem } from "@/components/notificacoes/notification-item";
import { markAsRead, markAllAsRead } from "./actions";

type Notification = {
  id: string;
  type: string;
  title: string;
  message: string | null;
  resource_type: string | null;
  resource_id: string | null;
  read_at: string | null;
  created_at: string;
};

export default async function NotificacoesPage() {
  const user = await getCurrentUser();
  if (!user) redirect("/login");

  const supabase = await createClient();
  const { data: notifications } = await supabase
    .from("notifications")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(50)
    .returns<Notification[]>();

  const unreadCount = notifications?.filter((n) => !n.read_at).length ?? 0;

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-md flex-col gap-6 px-5 py-10">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Notificações</h1>
        {unreadCount > 0 && (
          <span className="rounded-full bg-red-600 px-2.5 py-0.5 text-xs font-semibold text-white">
            {unreadCount}
          </span>
        )}
      </div>

      {unreadCount > 0 && (
        <form action={markAllAsRead}>
          <button
            type="submit"
            className="text-sm font-medium text-gray-700 underline"
          >
            Marcar todas como lidas
          </button>
        </form>
      )}

      {!notifications || notifications.length === 0 ? (
        <p className="text-gray-600">Nenhuma notificação.</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {notifications.map((notification) => (
            <NotificationItem
              key={notification.id}
              notification={notification}
              markAsRead={markAsRead}
              formatDateTime={formatDateTime}
            />
          ))}
        </ul>
      )}
    </main>
  );
}
