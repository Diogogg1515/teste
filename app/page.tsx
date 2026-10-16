import type { Metadata } from "next";
import Link from "next/link";
import { WORKER_INFO } from "@/lib/worker-info";

export const metadata: Metadata = {
  title: "souza.l — Serviços hidráulicos com documentação profissional",
  description: `${WORKER_INFO.name}, ${WORKER_INFO.profession} em ${WORKER_INFO.region}. Serviços documentados e organizados.`,
};

export default function HomePage() {
  const whatsappUrl = `https://wa.me/${WORKER_INFO.whatsapp}?text=${encodeURIComponent("Olá! Vi seu perfil no souza.l e gostaria de solicitar um orçamento.")}`;

  return (
    <div className="min-h-screen bg-white">
      {/* Header */}
      <header className="sticky top-0 z-50 border-b border-gray-200 bg-white/95 backdrop-blur">
        <nav className="mx-auto flex max-w-5xl items-center justify-between px-5 py-4">
          <Link href="/" className="text-xl font-bold text-gray-900">
            souza.l
          </Link>
          <div className="flex items-center gap-4 text-sm">
            <Link href="/login" className="text-gray-600 hover:text-gray-900">
              Entrar
            </Link>
            <Link
              href="/painel"
              className="rounded-lg bg-gray-900 px-4 py-2 font-medium text-white hover:bg-gray-800"
            >
              Meus Serviços
            </Link>
          </div>
        </nav>
      </header>

      <main>
        {/* Hero */}
        <section className="mx-auto max-w-5xl px-5 py-16 md:py-24">
          <div className="flex flex-col gap-6">
            <div className="inline-flex items-center gap-2 text-sm font-medium text-gray-600">
              <span className="h-2 w-2 rounded-full bg-green-500" />
              Disponível em {WORKER_INFO.region}
            </div>

            <h1 className="text-4xl font-bold text-gray-900 md:text-5xl">
              {WORKER_INFO.name}
            </h1>

            <p className="text-xl text-gray-600 md:text-2xl">
              {WORKER_INFO.profession}
            </p>

            <p className="max-w-2xl text-lg text-gray-600">
              {WORKER_INFO.description}
            </p>

            <div className="flex flex-col gap-3 sm:flex-row">
              <a
                href={whatsappUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex h-12 items-center justify-center rounded-lg bg-green-600 px-6 text-base font-medium text-white hover:bg-green-700"
              >
                Solicitar Orçamento via WhatsApp
              </a>
              <a
                href="#servicos"
                className="inline-flex h-12 items-center justify-center rounded-lg border border-gray-300 px-6 text-base font-medium text-gray-900 hover:bg-gray-50"
              >
                Ver Serviços
              </a>
            </div>
          </div>
        </section>

        {/* Serviços */}
        <section
          id="servicos"
          className="border-t border-gray-200 bg-gray-50 py-16 md:py-24"
        >
          <div className="mx-auto max-w-5xl px-5">
            <h2 className="mb-8 text-3xl font-bold text-gray-900">
              Serviços Oferecidos
            </h2>
            <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {WORKER_INFO.services.map((service) => (
                <li
                  key={service}
                  className="rounded-xl border border-gray-200 bg-white p-6"
                >
                  <span className="text-lg font-medium text-gray-900">
                    {service}
                  </span>
                </li>
              ))}
            </ul>
          </div>
        </section>

        {/* Trabalhos */}
        <section id="trabalhos" className="py-16 md:py-24">
          <div className="mx-auto max-w-5xl px-5">
            <h2 className="mb-8 text-3xl font-bold text-gray-900">Trabalhos</h2>
            <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
              {WORKER_INFO.workSamples.map((work, index) => (
                <div
                  key={index}
                  className="overflow-hidden rounded-xl border border-gray-200 bg-gray-100"
                >
                  <div className="aspect-video bg-gray-200 flex items-center justify-center">
                    <span className="text-sm text-gray-500">Foto em breve</span>
                  </div>
                  <div className="p-4">
                    <h3 className="font-medium text-gray-900">{work.title}</h3>
                    <p className="mt-1 text-sm text-gray-600">
                      {work.description}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Sobre */}
        <section
          id="sobre"
          className="border-t border-gray-200 bg-gray-50 py-16 md:py-24"
        >
          <div className="mx-auto max-w-5xl px-5">
            <h2 className="mb-8 text-3xl font-bold text-gray-900">Sobre</h2>
            <p className="max-w-3xl whitespace-pre-line text-lg text-gray-600">
              {WORKER_INFO.about}
            </p>
          </div>
        </section>

        {/* CTA Final */}
        <section className="py-16 md:py-24">
          <div className="mx-auto max-w-5xl px-5">
            <div className="rounded-2xl bg-gray-900 p-8 text-center md:p-12">
              <h2 className="mb-4 text-3xl font-bold text-white">
                Pronto para começar?
              </h2>
              <p className="mb-6 text-lg text-gray-300">
                Entre em contato e solicite seu orçamento sem compromisso.
              </p>
              <a
                href={whatsappUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex h-12 items-center justify-center rounded-lg bg-green-600 px-8 text-base font-medium text-white hover:bg-green-700"
              >
                Falar no WhatsApp
              </a>
            </div>
          </div>
        </section>
      </main>

      {/* Footer */}
      <footer className="border-t border-gray-200 py-8">
        <div className="mx-auto max-w-5xl px-5 text-center text-sm text-gray-600">
          <p>
            © {new Date().getFullYear()} souza.l — Conectando clientes e
            profissionais com transparência.
          </p>
        </div>
      </footer>

      {/* Botão flutuante WhatsApp (mobile) */}
      <a
        href={whatsappUrl}
        target="_blank"
        rel="noopener noreferrer"
        className="fixed bottom-6 right-6 z-50 flex h-14 w-14 items-center justify-center rounded-full bg-green-600 text-2xl text-white shadow-lg hover:bg-green-700 md:hidden"
        aria-label="WhatsApp"
      >
        💬
      </a>
    </div>
  );
}
