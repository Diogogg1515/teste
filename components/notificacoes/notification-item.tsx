"use client";

import Link from "next/link";
import { useTransition } from "react";

type Notification = {
  id: string;
  type: string;
  title: string;
  message: string | null;
  resource_type: string | null;
  resource_id: string | null;
  read_at: string | null;
  created_at: string;
};

type Props = {
  notification: Notification;
  markAsRead: (id: string) => Promise<{ error?: string; success?: boolean }>;
  formatDateTime: (iso: string) => string;
};

const TYPE_ICONS: Record<string, string> = {
  service_request_received: "📬",
  service_request_accepted: "✅",
  service_request_rejected: "❌",
  service_status_changed: "🔄",
  service_invite_received: "📨",
  default: "🔔",
};

export function NotificationItem({
  notification,
  markAsRead,
  formatDateTime,
}: Props) {
  const [isPending, startTransition] = useTransition();
  const isUnread = !notification.read_at;

  const handleClick = () => {
    if (isUnread) {
      startTransition(async () => {
        await markAsRead(notification.id);
      });
    }
  };

  const icon = TYPE_ICONS[notification.type] ?? TYPE_ICONS.default;
  const hasResource =
    notification.resource_type && notification.resource_id;
  const resourceHref = hasResource
    ? `/${notification.resource_type === "service" ? "servicos" : notification.resource_type}/${notification.resource_id}`
    : null;

  const content = (
    <div
      className={`flex gap-3 rounded-xl border p-4 ${
        isUnread
          ? "border-blue-200 bg-blue-50"
          : "border-gray-200 bg-white"
      } ${isPending ? "opacity-50" : ""}`}
    >
      <span className="text-2xl" aria-hidden="true">
        {icon}
      </span>
      <div className="flex min-w-0 flex-1 flex-col gap-1">
        <div className="flex items-start justify-between gap-2">
          <h3 className="font-semibold">{notification.title}</h3>
          {isUnread && (
            <span
              className="mt-1 h-2 w-2 flex-shrink-0 rounded-full bg-blue-600"
              aria-label="Não lida"
            />
          )}
        </div>
        {notification.message && (
          <p className="text-sm text-gray-700">{notification.message}</p>
        )}
        <time className="text-xs text-gray-500">
          {formatDateTime(notification.created_at)}
        </time>
      </div>
    </div>
  );

  if (resourceHref) {
    return (
      <li>
        <Link href={resourceHref} onClick={handleClick}>
          {content}
        </Link>
      </li>
    );
  }

  return (
    <li>
      <button
        type="button"
        onClick={handleClick}
        className="w-full text-left"
        disabled={isPending}
      >
        {content}
      </button>
    </li>
  );
}
