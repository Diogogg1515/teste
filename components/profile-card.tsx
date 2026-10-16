import type { PublicProfile } from "@/lib/profiles/public-profile";

export function ProfileCard({ profile }: { profile: PublicProfile }) {
  return (
    <article className="flex flex-col gap-3 rounded-2xl border border-gray-200 p-5">
      <div>
        <h3 className="text-xl font-semibold">{profile.displayName}</h3>
        <p className="text-gray-600">
          {profile.profession}
          {profile.region ? ` · ${profile.region}` : ""}
        </p>
      </div>

      {profile.description && (
        <p className="text-base leading-relaxed">{profile.description}</p>
      )}

      {profile.services.length > 0 && (
        <ul className="flex flex-wrap gap-2">
          {profile.services.map((service) => (
            <li
              key={service}
              className="rounded-full bg-gray-100 px-3 py-1 text-sm text-gray-800"
            >
              {service}
            </li>
          ))}
        </ul>
      )}
    </article>
  );
}
