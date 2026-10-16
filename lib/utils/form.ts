/**
 * Valida UUID v4 (formato padrão do Supabase/Postgres).
 * Aceita letras minúsculas ou maiúsculas.
 */
export function isUuid(value: string): boolean {
  if (typeof value !== "string") return false;
  const uuidRegex =
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  return uuidRegex.test(value);
}