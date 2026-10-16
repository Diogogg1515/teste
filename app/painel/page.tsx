import Link from "next/link";
import { redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth/get-user";
import { listMyServices } from "@/lib/services/list";
import { listPendingRequests } from "@/lib/services/requests";
import { listMyClients } from "@/lib/clients/list";
import { countUnreadNotifications } from "@/lib/notifications/count";
import { STATUS_LABELS, STATUS_DOT } from "@/lib/services/status";
import { CopyCodeButton } from "@/components/client-code/copy-button";
import { logout } from "./actions";

type Props = { searchParams: Promise<{ aceito?: string }> };

export default async function PainelPage({ searchParams }: Props) {
  const user = await getCurrentUser();

  if (!user) {
    redirect("/login");
  }

  const { aceito } = await searchParams;
  const { profile } = user;
  const role = profile?.role;

  // Admin vai para página específica
  if (role === "admin") {
    redirect("/admin");
  }

  const isWorker = role === "worker";
  const isClient = role === "client";

  // Dados por papel
  const [services, requests, clients, unreadCount] = await Promise.all([
    isWorker || isClient ? listMyServices() : [],
    isClient ? listPendingRequests() : [],
    isWorker ? listMyClients() : [],
    countUnreadNotifications(),
  ]);

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-md flex-col gap-6 px-5 py-10">
      {/* Header */}
      <header className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">Painel</h1>
          {profile && (
            <p className="text-sm text-gray-600">Olá, {profile.name}</p>
          )}
        </div>
        <Link
          href="/notificacoes"
          className="relative rounded-lg border border-gray-300 p-3"
        >
          <span className="text-lg">🔔</span>
          {unreadCount > 0 && (
            <span className="absolute -right-1 -top-1 flex h-5 w-5 items-center justify-center rounded-full bg-red-600 text-xs font-bold text-white">
              {unreadCount > 9 ? "9+" : unreadCount}
            </span>
          )}
        </Link>
      </header>

      {aceito === "1" && (
        <p
          role="status"
          className="rounded-lg bg-green-50 p-3 text-sm text-green-900"
        >
          Serviço criado! O profissional foi avisado.
        </p>
      )}

      {/* Painel do Cliente */}
      {isClient && (
        <>
          {/* Código do Cliente */}
          {profile?.clientCode && (
            <section className="rounded-2xl border border-gray-200 bg-blue-50 p-4">
              <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-gray-600">
                Seu Código
              </h2>
              <div className="flex items-center justify-between gap-3">
                <span className="text-3xl font-bold tracking-wider">
                  {profile.clientCode}
                </span>
                <CopyCodeButton code={profile.clientCode} />
              </div>
              <p className="mt-2 text-xs text-gray-600">
                Forneça este código ao profissional para ele criar o serviço.
              </p>
            </section>
          )}

          {/* Pedidos Pendentes */}
          {requests.length > 0 && (
            <section className="flex flex-col gap-3">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500">
                Pedidos de Serviço ({requests.length})
              </h2>
              <ul className="flex flex-col gap-2">
                {requests.map((request) => (
                  <li key={request.id}>
                    <Link
                      href={`/pedidos/${request.id}`}
                      className="flex flex-col gap-1 rounded-xl border border-orange-300 bg-orange-50 p-4"
                    >
                      <span className="font-medium">{request.serviceType}</span>
                      <span className="text-sm text-gray-600">
                        De: {request.workerName}
                      </span>
                      <span className="text-xs text-gray-500">
                        Aguardando sua resposta
                      </span>
                    </Link>
                  </li>
                ))}
              </ul>
            </section>
          )}

          {/* Meus Serviços */}
          <section className="flex flex-col gap-3">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500">
              Meus Serviços
            </h2>
            {services.length === 0 ? (
              <p className="text-gray-600">Nenhum serviço ainda.</p>
            ) : (
              <ul className="flex flex-col gap-2">
                {services.map((service) => (
                  <li key={service.id}>
                    <Link
                      href={`/servicos/${service.id}`}
                      className="flex items-center justify-between gap-3 rounded-xl border border-gray-200 p-4"
                    >
                      <div className="flex flex-col gap-1">
                        <span className="font-medium">
                          Serviço #{String(service.number).padStart(3, "0")}
                        </span>
                        <span className="text-sm text-gray-600">
                          {service.serviceType}
                        </span>
                      </div>
                      <span
                        className={`flex items-center gap-2 text-sm ${
                          service.status === "completed"
                            ? "text-green-700"
                            : "text-gray-600"
                        }`}
                      >
                        <span
                          className={`h-2 w-2 rounded-full ${STATUS_DOT[service.status as keyof typeof STATUS_DOT]}`}
                        />
                        {STATUS_LABELS[service.status as keyof typeof STATUS_LABELS]}
                      </span>
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      )}

      {/* Painel do Trabalhador */}
      {isWorker && (
        <>
          {/* Ação Principal */}
          <Link
            href="/pedidos/novo"
            className="flex h-14 items-center justify-center rounded-xl bg-blue-600 text-lg font-semibold text-white hover:bg-blue-700"
          >
            + Novo Serviço
          </Link>

          {/* Clientes Recentes */}
          {clients.length > 0 && (
            <section className="flex flex-col gap-3">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500">
                Clientes Recentes
              </h2>
              <ul className="flex flex-col gap-2">
                {clients.slice(0, 5).map((client) => (
                  <li key={client.id}>
                    <Link
                      href={`/clientes/${client.id}`}
                      className="flex items-center justify-between rounded-xl border border-gray-200 p-3"
                    >
                      <span className="font-medium">{client.name}</span>
                      <span className="text-sm text-gray-600">
                        {client.servicesCount}{" "}
                        {client.servicesCount === 1 ? "serviço" : "serviços"}
                      </span>
                    </Link>
                  </li>
                ))}
              </ul>
              <Link href="/clientes" className="text-center text-sm underline">
                Ver todos os clientes
              </Link>
            </section>
          )}

          {/* Serviços */}
          <section className="flex flex-col gap-3">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500">
              Serviços
            </h2>
            {services.length === 0 ? (
              <p className="text-gray-600">Nenhum serviço ainda.</p>
            ) : (
              <ul className="flex flex-col gap-2">
                {services.map((service) => (
                  <li key={service.id}>
                    <Link
                      href={`/servicos/${service.id}`}
                      className="flex items-center justify-between gap-3 rounded-xl border border-gray-200 p-4"
                    >
                      <div className="flex flex-col gap-1">
                        <span className="font-medium">
                          Serviço #{String(service.number).padStart(3, "0")}
                        </span>
                        <span className="text-sm text-gray-600">
                          {service.serviceType}
                        </span>
                      </div>
                      <span
                        className={`flex items-center gap-2 text-sm ${
                          service.status === "completed"
                            ? "text-green-700"
                            : "text-gray-600"
                        }`}
                      >
                        <span
                          className={`h-2 w-2 rounded-full ${STATUS_DOT[service.status as keyof typeof STATUS_DOT]}`}
                        />
                        {STATUS_LABELS[service.status as keyof typeof STATUS_LABELS]}
                      </span>
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      )}

      {/* Sair */}
      <form action={logout} className="mt-4">
        <button
          type="submit"
          className="h-12 w-full rounded-lg border border-gray-300 text-base font-medium hover:bg-gray-50"
        >
          Sair
        </button>
      </form>

      {/* Link para home */}
      <Link href="/" className="text-center text-sm text-gray-600 underline">
        Voltar para a página inicial
      </Link>
    </main>
  );
}
