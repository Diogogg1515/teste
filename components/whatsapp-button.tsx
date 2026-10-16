export function WhatsAppButton({
  phone,
  name,
}: {
  phone: string;
  name: string;
}) {
  const digits = phone.replace(/\D/g, "");
  const message = `Olá, ${name}! Vi seu perfil no souza.l e gostaria de pedir um orçamento.`;
  const href = `https://wa.me/${digits}?text=${encodeURIComponent(message)}`;

  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className="flex h-12 w-full items-center justify-center rounded-lg bg-gray-900 text-base font-medium text-white"
    >
      Pedir orçamento
    </a>
  );
}
