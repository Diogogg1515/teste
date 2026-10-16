export type ServiceStatus =
  | "in_progress"
  | "waiting_response"
  | "interrupted"
  | "completed"
  | "cancelled";

export const STATUS_LABELS: Record<ServiceStatus, string> = {
  in_progress: "Em andamento",
  waiting_response: "Aguardando resposta",
  interrupted: "Interrompido",
  completed: "Concluído",
  cancelled: "Cancelado",
};

// Cor do ponto de status (o texto sempre acompanha: a cor nunca vem sozinha).
export const STATUS_DOT: Record<ServiceStatus, string> = {
  in_progress: "bg-blue-600",
  waiting_response: "bg-amber-500",
  interrupted: "bg-gray-500",
  completed: "bg-green-600",
  cancelled: "bg-red-600",
};

// Só nestes estados cabem novos registros (o banco também confere).
export const RECORDS_OPEN: ServiceStatus[] = ["in_progress", "waiting_response"];

export const ALL_STATUSES = Object.keys(STATUS_LABELS) as ServiceStatus[];

export type StatusAction = {
  to: ServiceStatus;
  label: string;
  confirm: boolean; // pede confirmação antes (não volta atrás)
};

// Ações de status do profissional. O banco confere de novo cada transição:
// este mapa só decide quais botões aparecem.
export const STATUS_ACTIONS: Record<ServiceStatus, StatusAction[]> = {
  in_progress: [
    { to: "waiting_response", label: "Aguardando resposta do cliente", confirm: false },
    { to: "interrupted", label: "Interromper serviço", confirm: false },
    { to: "completed", label: "Concluir serviço", confirm: true },
    { to: "cancelled", label: "Cancelar serviço", confirm: true },
  ],
  waiting_response: [
    { to: "in_progress", label: "Voltar para em andamento", confirm: false },
    { to: "completed", label: "Concluir serviço", confirm: true },
    { to: "cancelled", label: "Cancelar serviço", confirm: true },
  ],
  interrupted: [
    { to: "in_progress", label: "Retomar serviço", confirm: false },
    { to: "completed", label: "Concluir serviço", confirm: true },
    { to: "cancelled", label: "Cancelar serviço", confirm: true },
  ],
  completed: [],
  cancelled: [],
};
