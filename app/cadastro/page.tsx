import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { safeNext } from "@/lib/auth/safe-next";
import { SignupForm } from "./signup-form";

type Props = { searchParams: Promise<{ next?: string }> };

export default async function CadastroPage({ searchParams }: Props) {
  const { next } = await searchParams;
  const target = safeNext(next);

  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();

  if (data?.claims) {
    redirect(target);
  }

  // Mantém o destino (por exemplo, um convite) ao ir para o login.
  const query = next ? `?next=${encodeURIComponent(target)}` : "";

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-sm flex-col justify-center gap-6 p-6">
      <h1 className="text-2xl font-semibold">Criar conta</h1>
      <SignupForm next={target} />
      <p className="text-sm">
        Já tem conta?{" "}
        <Link href={`/login${query}`} className="underline">
          Entrar
        </Link>
      </p>
    </main>
  );
}
