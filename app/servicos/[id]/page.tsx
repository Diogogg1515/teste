import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth/get-user";
import {
  getCounterpart,
  getService,
  listRecords,
} from "@/lib/services/detail";
import { listServiceDocuments } from "@/lib/documents/list";
import { formatDateTime } from "@/lib/services/format";
import {
  RECORDS_OPEN,
  STATUS_ACTIONS,
  STATUS_DOT,
  STATUS_LABELS,
} from "@/lib/services/status";
import { PhotoGallery } from "@/components/gallery/photo-gallery";
import { changeStatus } from "./actions";
import { requestLaudo, generateLaudoAction } from "./laudo-actions";
import { RecordForm } from "./record-form";

export const metadata: Metadata = { title: "Serviço | souza.l" };

type Props = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ erro?: string; novo?: string }>;
};

export default async function ServicoPage({ params, searchParams }: Props) {
  const user = await getCurrentUser();

  // Segunda verificação, além do proxy.
  if (!user) {
    redirect("/login");
  }

  // O administrador não acessa o conteúdo dos serviços.
  const role = user.profile?.role;
  if (role !== "client" && role !== "worker") {
    redirect("/painel");
  }

  const { id } = await params;
  const { erro, novo } = await searchParams;

  // O banco só devolve o serviço a quem participa dele. Para qualquer outra
  // pessoa, o resultado é o mesmo de um serviço que não existe.
  const service = await getService(id);
  if (!service) {
    notFound();
  }

  const [records, counterpart, documents] = await Promise.all([
    listRecords(service.id),
    getCounterpart(service.id),
    listServiceDocuments(service.id),
  ]);

  const isWorker = role === "worker";
  const isClient = role === "client";
  const canAddRecord = RECORDS_OPEN.includes(service.status);
  const actions = isWorker ? STATUS_ACTIONS[service.status] : [];
  const isCompleted = service.status === "completed";

  const laudoRequested = documents.some((d) => d.documentType === "laudo_requested");
  const laudo = documents.find((d) => d.documentType === "laudo");
  const canRequestLaudo = isClient && isCompleted && !laudoRequested && !laudo;

  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "";
  const notifyText = `Olá! Atualizei o serviço #${String(service.number).padStart(3, "0")} no souza.l: ${siteUrl}/servicos/${service.id}`;
  const notifyUrl = `https://wa.me/?text=${encodeURIComponent(notifyText)}`;

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-md flex-col gap-6 px-5 py-10">
      {novo === "1" && (
        <p
          role="status"
          className="rounded-lg bg-green-50 p-3 text-sm text-green-900"
        >
          Serviço criado! O profissional foi avisado.
        </p>
      )}
      {erro === "status" && (
        <p role="alert" className="rounded-lg bg-red-50 p-3 text-sm text-red-900">
          Não foi possível mudar o status. Confira se essa mudança é permitida
          e tente de novo.
        </p>
      )}

      <header className="flex flex-col gap-2">
        <p className="text-sm font-semibold uppercase tracking-wide text-gray-500">
          Serviço #{String(service.number).padStart(3, "0")}
        </p>
        <h1 className="text-2xl font-semibold">{service.serviceType}</h1>

        <span className="inline-flex items-center gap-2 text-base">
          <span
            aria-hidden="true"
            className={`h-3 w-3 rounded-full ${STATUS_DOT[service.status]}`}
          />
          {STATUS_LABELS[service.status]}
        </span>

        <p className="text-base">{service.address}</p>

        {counterpart && (
          <p className="text-sm text-gray-600">
            {counterpart.role === "worker" ? "Profissional" : "Cliente"}:{" "}
            <strong>{counterpart.name}</strong>
          </p>
        )}
        <p className="text-sm text-gray-600">
          Criado em {formatDateTime(service.createdAt)}
          {service.completedAt &&
            ` · encerrado em ${formatDateTime(service.completedAt)}`}
        </p>
      </header>

      {isWorker && actions.length > 0 && (
        <section
          aria-labelledby="acoes"
          className="flex flex-col gap-3 rounded-2xl border border-gray-200 p-4"
        >
          <h2
            id="acoes"
            className="text-sm font-semibold uppercase tracking-wide text-gray-500"
          >
            Status do serviço
          </h2>

          {actions.map((action) =>
            action.confirm ? (
              <details key={action.to} className="rounded-xl border border-gray-200 p-3">
                <summary className="cursor-pointer text-base font-medium">
                  {action.label}
                </summary>
                <form action={changeStatus} className="mt-3 flex flex-col gap-2">
                  <p className="text-sm text-gray-600">
                    Esta mudança não pode ser desfeita.
                  </p>
                  <input type="hidden" name="service_id" value={service.id} />
                  <input type="hidden" name="status" value={action.to} />
                  <button
                    type="submit"
                    className="h-12 rounded-lg bg-gray-900 text-base font-medium text-white"
                  >
                    Confirmar
                  </button>
                </form>
              </details>
            ) : (
              <form key={action.to} action={changeStatus}>
                <input type="hidden" name="service_id" value={service.id} />
                <input type="hidden" name="status" value={action.to} />
                <button
                  type="submit"
                  className="h-12 w-full rounded-lg border border-gray-300 text-base font-medium"
                >
                  {action.label}
                </button>
              </form>
            ),
          )}
        </section>
      )}

      <section aria-labelledby="registros" className="flex flex-col gap-3">
        <h2
          id="registros"
          className="text-sm font-semibold uppercase tracking-wide text-gray-500"
        >
          Registros
        </h2>

        {records.length === 0 ? (
          <p className="text-gray-600">Nenhum registro ainda.</p>
        ) : (
          <ol className="flex flex-col gap-3">
            {records.map((record) => (
              <li
                key={record.id}
                className={`flex flex-col gap-1 rounded-xl border-l-4 bg-gray-50 p-4 ${
                  record.authorRole === "client"
                    ? "border-blue-500"
                    : "border-gray-900"
                }`}
              >
                <div className="flex flex-col gap-2">
                  <span className="text-sm font-semibold">
                    {record.authorRole === "client"
                      ? "Registro do Cliente"
                      : "Registro do Trabalhador"}
                  </span>
                  <span className="text-xs text-gray-600">
                    {formatDateTime(record.createdAt)}
                  </span>
                  <p className="whitespace-pre-wrap break-words text-base">
                    {record.content}
                  </p>

                  {/* Galeria de fotos */}
                  {record.files.length > 0 && (
                    <div className="mt-3">
                      <PhotoGallery
                        photos={record.files
                          .filter((f) => f.mimeType.startsWith("image/"))
                          .map((file) => ({
                            id: file.id,
                            url: `/api/storage/service-files/${file.id}`,
                            caption: file.caption,
                            originalName: file.originalName,
                          }))}
                      />
                    </div>
                  )}
                </div>
              </li>
            ))}
          </ol>
        )}
      </section>

      {canAddRecord ? (
        <RecordForm serviceId={service.id} role={role} />
      ) : (
        <p className="rounded-lg bg-gray-100 p-3 text-sm">
          Este serviço está &quot;{STATUS_LABELS[service.status]}&quot;. Novos
          registros estão bloqueados.
        </p>
      )}

      {isWorker && (
        <a
          href={notifyUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="flex h-12 items-center justify-center rounded-lg border border-gray-300 text-base font-medium"
        >
          Avisar cliente no WhatsApp
        </a>
      )}

      {/* Seção Laudo */}
      {isCompleted && (
        <section className="flex flex-col gap-3 rounded-2xl border border-gray-200 bg-gray-50 p-4">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500">
            Laudo do Serviço
          </h2>

          {laudo ? (
            // Laudo pronto para download
            <div className="flex flex-col gap-3">
              <p className="text-sm text-green-700">
                ✓ Laudo disponível para download
              </p>
              <a
                href={`/api/documents/${laudo.id}/download`}
                className="flex h-12 items-center justify-center rounded-lg bg-blue-600 text-base font-medium text-white hover:bg-blue-700"
              >
                Baixar Laudo (PDF)
              </a>
            </div>
          ) : laudoRequested ? (
            // Solicitação pendente
            <div className="flex flex-col gap-3">
              {isClient && (
                <p className="text-sm text-orange-700">
                  ⏳ Laudo solicitado. Aguardando geração pelo profissional.
                </p>
              )}
              {isWorker && (
                <>
                  <p className="text-sm text-orange-700">
                    O cliente solicitou o laudo deste serviço.
                  </p>
                  <form action={generateLaudoAction.bind(null, service.id)}>
                    <button
                      type="submit"
                      className="flex h-12 w-full items-center justify-center rounded-lg bg-gray-900 text-base font-medium text-white hover:bg-gray-800"
                    >
                      Gerar Laudo
                    </button>
                  </form>
                </>
              )}
            </div>
          ) : canRequestLaudo ? (
            // Cliente pode solicitar
            <div className="flex flex-col gap-3">
              <p className="text-sm text-gray-600">
                Solicite o laudo oficial do serviço em formato PDF.
              </p>
              <form action={requestLaudo.bind(null, service.id)}>
                <button
                  type="submit"
                  className="flex h-12 w-full items-center justify-center rounded-lg border border-gray-900 text-base font-medium hover:bg-gray-50"
                >
                  Solicitar Laudo
                </button>
              </form>
            </div>
          ) : (
            isClient && (
              <p className="text-sm text-gray-600">
                O laudo poderá ser solicitado após a conclusão do serviço.
              </p>
            )
          )}
        </section>
      )}

      {/* Download Informações Completas */}
      <section className="flex flex-col gap-3 rounded-2xl border border-gray-200 p-4">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500">
          Backup de Dados
        </h2>
        <p className="text-sm text-gray-600">
          Baixe todas as informações registradas até o momento. Este serviço expira em{" "}
          {new Date(service.expiresAt).toLocaleDateString("pt-BR")}.
        </p>
        <div className="flex flex-col gap-2 sm:flex-row">
          <a
            href={`/api/services/${service.id}/export?format=txt`}
            download
            className="flex h-10 flex-1 items-center justify-center rounded-lg border border-gray-300 text-sm font-medium hover:bg-gray-50"
          >
            Baixar TXT
          </a>
          <a
            href={`/api/services/${service.id}/export?format=json`}
            download
            className="flex h-10 flex-1 items-center justify-center rounded-lg border border-gray-300 text-sm font-medium hover:bg-gray-50"
          >
            Baixar JSON
          </a>
        </div>
      </section>

      <Link href="/painel" className="text-center text-sm underline">
        Voltar ao painel
      </Link>
    </main>
  );
}
