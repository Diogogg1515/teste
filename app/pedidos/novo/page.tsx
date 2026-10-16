import Link from "next/link";
import { requireRole } from "@/lib/auth/require-role";
import { InviteForm } from "./invite-form";

type Props = { searchParams: Promise<Record<string, string>> };

export default async function NovoPedidoPage({ searchParams }: Props) {
  await requireRole(["worker"]);

  await searchParams;

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-md flex-col gap-6 px-5 py-10">
      <div className="flex flex-col gap-2">
        <h1 className="text-2xl font-semibold">Novo pedido</h1>
        <p className="text-gray-600">
          Crie um convite e envie o link pelo WhatsApp. O cliente aceita
          criando a conta na hora.
        </p>
      </div>

      <InviteForm visitId={null} defaultName={""} />

      <Link href="/painel" className="text-center text-sm underline">
        Voltar ao painel
      </Link>
    </main>
  );
}
