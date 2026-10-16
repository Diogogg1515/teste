import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { safeNext } from "@/lib/auth/safe-next";
import { LoginForm } from "./login-form";

type Props = { searchParams: Promise<{ next?: string }> };

export default async function LoginPage({ searchParams }: Props) {
  const { next } = await searchParams;
  const target = safeNext(next);

  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();

  // Quem já está logado não precisa ver a tela de login.
  if (data?.claims) {
    redirect(target);
  }

  // Mantém o destino (por exemplo, um convite) ao ir para o cadastro.
  const query = next ? `?next=${encodeURIComponent(target)}` : "";

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-sm flex-col justify-center gap-6 p-6">
      <h1 className="text-2xl font-semibold">Entrar</h1>
      <LoginForm next={target} />
      <div className="flex flex-col gap-2 text-sm">
        <p>
          <Link href="/recuperar-senha" className="underline">
            Esqueci minha senha
          </Link>
        </p>
        <p>
          Não tem conta?{" "}
          <Link href={`/cadastro${query}`} className="underline">
            Criar conta
          </Link>
        </p>
      </div>
    </main>
  );
}
