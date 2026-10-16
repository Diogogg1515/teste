import Link from "next/link";
import { requireRole } from "@/lib/auth/require-role";

export default async function AdminPage() {
  await requireRole(["admin"]);

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-sm flex-col justify-center gap-4 p-6">
      <h1 className="text-2xl font-semibold">Administração</h1>
      <p>Área do administrador. As ferramentas de gestão vêm em uma etapa futura.</p>
      <Link href="/painel" className="text-sm underline">
        Voltar ao painel
      </Link>
    </main>
  );
}