"use client";

import { useState } from "react";

export function CopyButton({
  text,
  label = "Copiar link",
}: {
  text: string;
  label?: string;
}) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  }

  return (
    <button
      type="button"
      onClick={copy}
      className="h-12 w-full rounded-lg border border-gray-300 text-base font-medium"
    >
      {copied ? "Link copiado!" : label}
    </button>
  );
}
