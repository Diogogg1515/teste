import Link from "next/link";
import { ResetForm } from "./reset-form";

export default async function RecuperarSenhaPage({
  searchParams,
}: {
  searchParams: Promise<{ erro?: string }>;
}) {
  const { erro } = await searchParams;

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-sm flex-col justify-center gap-6 p-6">
      <h1 className="text-2xl font-semibold">Recuperar senha</h1>

      {erro === "link" && (
        <p role="alert" className="text-sm text-red-600">
          Esse link é inválido ou expirou. Peça um novo abaixo.
        </p>
      )}

      <ResetForm />

      <p className="text-sm">
        <Link href="/login" className="underline">
          Voltar para entrar
        </Link>
      </p>
    </main>
  );
}