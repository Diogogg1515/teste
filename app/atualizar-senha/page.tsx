import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { UpdateForm } from "./update-form";

export default async function AtualizarSenhaPage() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();

  // Só quem chegou pelo link do e-mail (ou já está logado) vê esta tela.
  if (!data?.claims) {
    redirect("/recuperar-senha?erro=link");
  }

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-sm flex-col justify-center gap-6 p-6">
      <h1 className="text-2xl font-semibold">Nova senha</h1>
      <UpdateForm />
    </main>
  );
}