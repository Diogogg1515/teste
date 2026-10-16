"use client";

import { useActionState } from "react";
import { acceptInvite, type AcceptState } from "./actions";

const initialState: AcceptState = { error: null };

export function AcceptForm({ token }: { token: string }) {
  const [state, formAction, pending] = useActionState(
    acceptInvite,
    initialState,
  );

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <input type="hidden" name="token" value={token} />

      <div className="flex flex-col gap-1">
        <label htmlFor="address" className="text-sm font-medium">
          Endereço onde o serviço será feito
        </label>
        <input
          id="address"
          name="address"
          type="text"
          autoComplete="street-address"
          required
          minLength={5}
          maxLength={300}
          className="h-12 rounded-lg border border-gray-300 px-3 text-base text-gray-900"
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
        {pending ? "Aceitando..." : "Aceitar serviço"}
      </button>
    </form>
  );
}
