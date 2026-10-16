import Link from "next/link";
import { requireRole } from "@/lib/auth/require-role";
import { listInvites, type InviteListItem } from "@/lib/invites/invites";
import { TIME_ZONE } from "@/lib/utils/time";
import { cancelInvite } from "./actions";

const STATE_LABELS: Record<InviteListItem["state"], string> = {
  pending: "Aguardando o cliente",
  accepted: "Aceito",
  cancelled: "Cancelado",
  expired: "Expirado",
};

const DATE_FORMAT = new Intl.DateTimeFormat("pt-BR", {
  timeZone: TIME_ZONE,
  day: "2-digit",
  month: "2-digit",
});

export default async function ConvitesPage() {
  await requireRole(["worker"]);

  const invites = await listInvites();

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-md flex-col gap-6 px-5 py-10">
      <h1 className="text-2xl font-semibold">Meus convites</h1>

      <Link
        href="/pedidos/novo"
        className="flex h-12 items-center justify-center rounded-lg bg-gray-900 text-base font-medium text-white"
      >
        Novo pedido
      </Link>

      {invites.length === 0 ? (
        <p className="text-gray-600">Nenhum convite criado ainda.</p>
      ) : (
        <ul className="flex flex-col gap-3">
          {invites.map((invite) => (
            <li
              key={invite.id}
              className="flex flex-col gap-2 rounded-xl border border-gray-200 p-4"
            >
              <span className="text-base">
                <strong>{invite.clientLabel}</strong> · {invite.serviceType}
              </span>
              <span className="text-sm text-gray-600">
                {STATE_LABELS[invite.state]}
                {invite.state === "pending" &&
                  ` · vale até ${DATE_FORMAT.format(new Date(invite.expiresAt))}`}
              </span>

              {invite.state === "pending" && (
                <form action={cancelInvite}>
                  <input type="hidden" name="id" value={invite.id} />
                  <button
                    type="submit"
                    className="h-10 rounded-lg border border-red-700 px-4 text-sm font-medium text-red-700"
                  >
                    Cancelar convite
                  </button>
                </form>
              )}
            </li>
          ))}
        </ul>
      )}

      <Link href="/painel" className="text-center text-sm underline">
        Voltar ao painel
      </Link>
    </main>
  );
}
