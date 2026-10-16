"use client";

import Link from "next/link";
import { useActionState } from "react";
import { CopyButton } from "@/components/copy-button";
import { createInvite, type InviteFormState } from "./actions";

const initialState: InviteFormState = {
  error: null,
  link: null,
  whatsappUrl: null,
};

const inputClass =
  "h-12 rounded-lg border border-gray-300 px-3 text-base text-gray-900";

export function InviteForm({
  visitId,
  defaultName,
}: {
  visitId: string | null;
  defaultName: string;
}) {
  const [state, formAction, pending] = useActionState(
    createInvite,
    initialState,
  );

  if (state.link && state.whatsappUrl) {
    return (
      <div className="flex flex-col gap-4">
        <p className="text-lg font-semibold">Convite criado!</p>
        <p className="break-all rounded-lg bg-gray-100 p-3 text-sm">
          {state.link}
        </p>

        <a
          href={state.whatsappUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="flex h-12 items-center justify-center rounded-lg bg-green-700 text-base font-medium text-white"
        >
          Enviar no WhatsApp
        </a>
        <CopyButton text={state.link} />

        <p className="text-sm text-gray-600">
          O link vale por 7 dias e só pode ser usado uma vez. Por segurança, ele
          não é mostrado de novo: se perder, cancele este convite e crie outro.
        </p>

        <Link href="/convites" className="text-center text-sm underline">
          Ver meus convites
        </Link>
      </div>
    );
  }

  return (
    <form action={formAction} className="flex flex-col gap-4">
      {visitId && <input type="hidden" name="visit_id" value={visitId} />}

      <div className="flex flex-col gap-1">
        <label htmlFor="service_type" className="text-sm font-medium">
          Tipo de serviço
        </label>
        <input
          id="service_type"
          name="service_type"
          type="text"
          required
          maxLength={100}
          placeholder="Ex.: troca de torneira"
          className={inputClass}
        />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="client_label" className="text-sm font-medium">
          Nome do cliente
        </label>
        <input
          id="client_label"
          name="client_label"
          type="text"
          required
          maxLength={100}
          defaultValue={defaultName}
          className={inputClass}
        />
      </div>

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}

      <button
        type="submit"
        disabled={pending}
        className="h-12 rounded-lg bg-gray-900 text-base font-medium text-white disabled:opacity-60"
      >
        {pending ? "Criando..." : "Criar convite"}
      </button>
    </form>
  );
}
