import Link from "next/link";
import type { ServiceSummary } from "@/lib/services/list";
import { STATUS_LABELS, type ServiceStatus } from "@/lib/services/status";

export function ServiceList({
  title,
  services,
}: {
  title: string;
  services: ServiceSummary[];
}) {
  return (
    <section aria-labelledby="servicos" className="flex flex-col gap-3">
      <h2
        id="servicos"
        className="text-sm font-semibold uppercase tracking-wide text-gray-500"
      >
        {title}
      </h2>

      {services.length === 0 ? (
        <p className="text-gray-600">Nenhum serviço por enquanto.</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {services.map((service) => (
            <li key={service.id}>
              <Link
                href={`/servicos/${service.id}`}
                className="flex flex-col gap-1 rounded-xl border border-gray-200 p-4"
              >
                <span className="text-base">
                  <strong>#{String(service.number).padStart(3, "0")}</strong> ·{" "}
                  {service.serviceType}
                </span>
                <span className="text-sm text-gray-600">
                  {STATUS_LABELS[service.status as ServiceStatus] ??
                    service.status}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
