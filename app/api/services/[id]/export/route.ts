import { NextResponse } from "next/server";
import { getCurrentUser } from "@/lib/auth/get-user";
import { exportServiceData, formatServiceExport } from "@/lib/documents/export-service";

type Context = {
  params: Promise<{ id: string }>;
};

export async function GET(request: Request, context: Context) {
  const user = await getCurrentUser();
  if (!user) {
    return NextResponse.json({ error: "Não autenticado" }, { status: 401 });
  }

  const { id } = await context.params;
  const url = new URL(request.url);
  const format = url.searchParams.get("format") || "txt"; // txt ou json

  // Busca dados (RLS já valida participação)
  const data = await exportServiceData(id);
  if (!data) {
    return NextResponse.json(
      { error: "Serviço não encontrado ou acesso negado" },
      { status: 404 }
    );
  }

  const serviceNumber = String(data.service.number).padStart(3, "0");
  const timestamp = new Date().toISOString().split("T")[0];

  if (format === "json") {
    // Download JSON
    const json = JSON.stringify(data, null, 2);
    const fileName = `servico-${serviceNumber}-${timestamp}.json`;

    return new NextResponse(json, {
      headers: {
        "Content-Type": "application/json",
        "Content-Disposition": `attachment; filename="${fileName}"`,
      },
    });
  }

  // Download TXT (padrão)
  const text = formatServiceExport(data);
  const fileName = `servico-${serviceNumber}-${timestamp}.txt`;

  return new NextResponse(text, {
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Content-Disposition": `attachment; filename="${fileName}"`,
    },
  });
}
