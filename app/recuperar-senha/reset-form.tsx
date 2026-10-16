"use client";

import { useActionState } from "react";
import { requestPasswordReset, type ResetState } from "./actions";

const initialState: ResetState = { error: null, info: null };

export function ResetForm() {
  const [state, formAction, pending] = useActionState(
    requestPasswordReset,
    initialState,
  );

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <label htmlFor="email" className="text-sm font-medium">
          E-mail
        </label>
        <input
          id="email"
          name="email"
          type="email"
          autoComplete="email"
          required
          className="h-12 rounded-lg border border-gray-300 px-3 text-base text-gray-900"
        />
      </div>

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}
      {state.info && (
        <p role="status" className="text-sm text-green-700">
          {state.info}
        </p>
      )}

      <button
        type="submit"
        disabled={pending}
        className="h-12 rounded-lg bg-gray-900 text-base font-medium text-white disabled:opacity-60"
      >
        {pending ? "Enviando..." : "Enviar link"}
      </button>
    </form>
  );
}