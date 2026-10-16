import { TIME_ZONE } from "@/lib/utils/time";

const FORMAT = new Intl.DateTimeFormat("pt-BR", {
  timeZone: TIME_ZONE,
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
});

// "04/10/2026 15:30", sempre no horário de Brasília
export function formatDateTime(iso: string): string {
  return FORMAT.format(new Date(iso));
}
