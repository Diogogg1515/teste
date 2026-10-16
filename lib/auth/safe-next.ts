// Só aceita caminhos internos do próprio site (evita desvio para outro endereço).
export function safeNext(
  value: FormDataEntryValue | string | null | undefined,
  fallback = "/painel",
): string {
  const path = typeof value === "string" ? value : "";
  const isInternal =
    path.startsWith("/") && !path.startsWith("//") && !path.startsWith("/\\");
  return isInternal ? path : fallback;
}
