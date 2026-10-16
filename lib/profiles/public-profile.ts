import { cache } from "react";
import { createClient } from "@/lib/supabase/server";

export type PublicProfile = {
  slug: string;
  displayName: string;
  profession: string;
  region: string | null;
  description: string | null;
  services: string[];
  whatsapp: string;
};

type Row = {
  slug: string;
  display_name: string;
  profession: string;
  region: string | null;
  description: string | null;
  services: string[] | null;
  whatsapp: string;
};

// Só colunas públicas: o banco não deixa visitantes lerem mais do que isso.
const COLUMNS =
  "slug, display_name, profession, region, description, services, whatsapp";

function toProfile(row: Row): PublicProfile {
  return {
    slug: row.slug,
    displayName: row.display_name,
    profession: row.profession,
    region: row.region,
    description: row.description,
    services: row.services ?? [],
    whatsapp: row.whatsapp,
  };
}

export const getPublicProfileBySlug = cache(
  async (slug: string): Promise<PublicProfile | null> => {
    if (!/^[a-z0-9-]{3,40}$/.test(slug)) {
      return null;
    }

    const supabase = await createClient();
    const { data, error } = await supabase
      .from("worker_profiles")
      .select(COLUMNS)
      .eq("slug", slug)
      .maybeSingle();

    if (error) {
      console.error("Erro ao buscar perfil público:", error.code);
      return null;
    }
    return data ? toProfile(data as Row) : null;
  },
);

// V1: existe um único profissional. Com vários, este critério será revisto.
export const getFeaturedProfile = cache(
  async (): Promise<PublicProfile | null> => {
    const supabase = await createClient();
    const { data, error } = await supabase
      .from("worker_profiles")
      .select(COLUMNS)
      .order("slug", { ascending: true })
      .limit(1)
      .maybeSingle();

    if (error) {
      console.error("Erro ao buscar perfil em destaque:", error.code);
      return null;
    }
    return data ? toProfile(data as Row) : null;
  },
);
