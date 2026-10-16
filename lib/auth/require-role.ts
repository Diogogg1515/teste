import { redirect } from "next/navigation";
import {
  getCurrentUser,
  type CurrentUser,
  type Profile,
  type UserRole,
} from "@/lib/auth/get-user";

type AuthorizedUser = CurrentUser & { profile: Profile };

// Use no topo de qualquer página restrita.
// O papel vem SEMPRE do banco (tabela profiles), nunca do navegador.
export async function requireRole(allowed: UserRole[]): Promise<AuthorizedUser> {
  const user = await getCurrentUser();

  if (!user) {
    redirect("/login");
  }

  if (!user.profile || !allowed.includes(user.profile.role)) {
    redirect("/painel");
  }

  return { ...user, profile: user.profile };
}