import { createClient } from "@/lib/supabase/server";

export type UserRole = "client" | "worker" | "admin";

export type Profile = {
  name: string;
  role: UserRole;
  clientCode: string | null;
};

export type CurrentUser = {
  id: string;
  email: string;
  profile: Profile | null;
};

// Retorna null se não houver login válido.
// O papel vem SEMPRE da tabela profiles (banco), nunca do navegador
// nem de metadados da conta, que o próprio usuário poderia alterar.
export async function getCurrentUser(): Promise<CurrentUser | null> {
  const supabase = await createClient();

  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims;
  if (!claims?.sub) {
    return null;
  }

  const { data: row } = await supabase
    .from("profiles")
    .select("name, role, client_code")
    .eq("id", claims.sub)
    .maybeSingle();

  return {
    id: claims.sub,
    email: String(claims.email ?? ""),
    profile: row
      ? {
          name: row.name,
          role: row.role as UserRole,
          clientCode: row.client_code,
        }
      : null,
  };
}