import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";
import { previewInvite, type InviteState } from "@/lib/invites/invites";
import { getCurrentUser } from "@/lib/auth/get-user";
import { AcceptForm } from "./accept-form";

// O link do convite é secreto: não aparece em buscadores nem vaza para outros sites.
export const metadata: Metadata = {
  title: "Convite | souza.l",
  robots: { index: false, follow: false },
  referrer: "no-referrer",
};

type Props = { params: Promise<{ token: string }> };

const UNAVAILABLE: Record<Exclude<InviteState, "valid">, string> = {
  expired: "Este convite expirou. Peça um novo ao profissional.",
  accepted: "Este convite já foi usado.",
  cancelled: "Este convite foi cancelado pelo profissional.",
};

function Shell({ children }: { children: ReactNode }) {
  return (
    <main className="mx-auto flex min-h-screen w-full max-w-md flex-col justify-center gap-6 px-5 py-10">
      {children}
    </main>
  );
}

export default async function ConvitePage({ params }: Props) {
  const { token } = await params;
  const invite = await previewInvite(token);

  if (!invite) {
    return (
      <Shell>
        <h1 className="text-2xl font-semibold">Convite não encontrado</h1>
        <p className="text-gray-600">
          Confira o link com quem enviou ou peça um novo.
        </p>
        <Link href="/" className="text-sm underline">
          Conhecer o souza.l
        </Link>
      </Shell>
    );
  }

  if (invite.state !== "valid") {
    return (
      <Shell>
        <h1 className="text-2xl font-semibold">Convite indisponível</h1>
        <p className="text-gray-600">{UNAVAILABLE[invite.state]}</p>
        <Link href="/" className="text-sm underline">
          Conhecer o souza.l
        </Link>
      </Shell>
    );
  }

  const user = await getCurrentUser();
  const nextQuery = `?next=${encodeURIComponent(`/convite/${token}`)}`;
  const isClient = user?.profile?.role === "client";

  return (
    <Shell>
      <div className="flex flex-col gap-2">
        <p className="text-sm font-semibold uppercase tracking-wide text-gray-500">
          Pedido de serviço
        </p>
        <h1 className="text-2xl font-semibold">
          {invite.workerName} enviou um pedido de serviço para você
        </h1>
        <p className="text-lg">
          Serviço: <strong>{invite.serviceType}</strong>
        </p>
      </div>

      {!user && (
        <div className="flex flex-col gap-3">
          <p className="text-sm text-gray-600">
            Para aceitar, crie uma conta gratuita. Leva menos de um minuto.
          </p>
          <Link
            href={`/cadastro${nextQuery}`}
            className="flex h-12 items-center justify-center rounded-lg bg-gray-900 text-base font-medium text-white"
          >
            Criar conta e aceitar
          </Link>
          <Link
            href={`/login${nextQuery}`}
            className="flex h-12 items-center justify-center rounded-lg border border-gray-300 text-base font-medium"
          >
            Já tenho conta
          </Link>
        </div>
      )}

      {user && isClient && <AcceptForm token={token} />}

      {user && !isClient && (
        <p className="rounded-lg bg-gray-100 p-3 text-sm">
          Este convite é para contas de cliente. Saia e entre com a conta do
          cliente para aceitar.
        </p>
      )}
    </Shell>
  );
}
