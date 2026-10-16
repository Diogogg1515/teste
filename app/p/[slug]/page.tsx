import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getPublicProfileBySlug } from "@/lib/profiles/public-profile";
import { ProfileCard } from "@/components/profile-card";
import { WhatsAppButton } from "@/components/whatsapp-button";

type Props = { params: Promise<{ slug: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const profile = await getPublicProfileBySlug(slug);

  if (!profile) {
    return { title: "Perfil não encontrado | souza.l" };
  }

  const title = `${profile.displayName} · ${profile.profession} | souza.l`;
  const description =
    profile.description ?? `${profile.profession} no souza.l`;

  return { title, description, openGraph: { title, description } };
}

export default async function PerfilPublicoPage({ params }: Props) {
  const { slug } = await params;
  const profile = await getPublicProfileBySlug(slug);

  if (!profile) {
    notFound();
  }

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-md flex-col gap-6 px-5 py-10">
      <ProfileCard profile={profile} />
      <WhatsAppButton phone={profile.whatsapp} name={profile.displayName} />
      <Link href="/" className="text-center text-sm underline">
        Conhecer o souza.l
      </Link>
    </main>
  );
}
