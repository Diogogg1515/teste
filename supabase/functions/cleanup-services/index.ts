// Edge Function: Limpeza automática de serviços expirados
// Executa diariamente via cron (configurar no Dashboard Supabase)
// Schedule recomendado: "0 3 * * *" (3h da manhã, horário servidor)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Apenas cron ou service role pode executar
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(
        JSON.stringify({ error: "Não autorizado" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    console.log("Iniciando limpeza de serviços expirados...");

    // 1. Notifica serviços próximos da expiração (30 dias antes)
    const { error: notifyError } = await supabase.rpc("notify_expiring_services");
    if (notifyError) {
      console.error("Erro ao notificar expiração:", notifyError);
    } else {
      console.log("Notificações de expiração enviadas");
    }

    // 2. Executa limpeza de serviços expirados (RPC enfileira arquivos no Storage)
    const { data: cleanupResult, error: cleanupError } = await supabase.rpc(
      "cleanup_expired_services"
    );

    if (cleanupError) {
      console.error("Erro na limpeza (RPC):", cleanupError);
      return new Response(
        JSON.stringify({ error: "Erro na limpeza (RPC)", details: cleanupError.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log("RPC de limpeza concluída:", cleanupResult);

    // 3. Processa fila de limpeza do Storage
    const batchSize = 50;

    while (true) {
      // Busca itens pendentes (máximo batchSize)
      const { data: queueItems, error: queueError } = await supabase.rpc(
        "get_pending_storage_cleanup",
        { p_limit: batchSize }
      );

      if (queueError) {
        console.error("Erro ao buscar fila de limpeza:", queueError);
        return new Response(
          JSON.stringify({ error: "Erro ao buscar fila de limpeza", details: queueError.message }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const items = queueItems ?? [];
      if (items.length === 0) {
        console.log("Fila de limpeza vazia - processamento concluído");
        break;
      }

      console.log(`Processando ${items.length} itens da fila de limpeza...`);

      // Processa cada item
      for (const item of items) {
        // Verifica se o item tem lease_token válido e não expirado
        if (!item.lease_token || !item.lease_expires_at || new Date(item.lease_expires_at) < new Date()) {
          console.warn(`Item ${item.id} com lease expirado ou inválido, pulando`);
          continue;
        }

        try {
          console.log(`Processando item ${item.id}: ${item.storage_path}`);

          const { error: storageError } = await supabase.storage
            .from(item.bucket)
            .remove([item.storage_path]);

          if (storageError) {
            console.error(`Erro ao excluir ${item.storage_path}:`, storageError);
            // Marca como falha - preserva para retry
            await supabase.rpc("mark_storage_cleanup_failed", {
              p_id: item.id,
              p_lease_token: item.lease_token,
              p_error: storageError.message,
              p_details: { bucket: item.bucket, path: item.storage_path, code: storageError.code }
            });
            continue;
          } else {
            // Sucesso no Storage - tenta marcar como completed
            const { data: completedOk, error: completedError } = await supabase.rpc(
              "mark_storage_cleanup_completed",
              { p_id: item.id, p_lease_token: item.lease_token }
            );

            if (completedError) {
              console.error(`Erro na RPC mark_completed para ${item.id}:`, completedError);
              // Erro na RPC de conclusão - marca como failed para retry
              await supabase.rpc("mark_storage_cleanup_failed", {
                p_id: item.id,
                p_lease_token: item.lease_token,
                p_error: `RPC mark_completed falhou: ${completedError.message}`,
                p_details: { rpc_error: completedError.message }
              });
              continue;
            }

            const completedOkBool = completedOk as boolean;
            if (!completedOkBool) {
              console.warn(`Token inválido ou item já processado por outra execução: ${item.id}`);
              // Token inválido ou item já processado por outra execução - não conta como falha
              continue;
            }

            // Sucesso total
            console.log(`Arquivo excluído e marcado como concluído: ${item.storage_path}`);
          }
        } catch (itemError) {
          console.error(`Erro inesperado ao processar ${item.id}:`, itemError);
          await supabase.rpc("mark_storage_cleanup_failed", {
            p_id: item.id,
            p_lease_token: item.lease_token,
            p_error: itemError.message,
            p_details: { stack: itemError.stack }
          });
        }
      }
    }

    // 3. Verifica resultado final
    if (cleanupResult?.error_count ?? 0 > 0) {
      console.warn("Limpeza concluída com erros na RPC:", {
        rpc_errors: cleanupResult?.error_count ?? 0,
        cleanup_result: cleanupResult
      });

      return new Response(
        JSON.stringify({
          success: false,
          error: "Limpeza concluída com erros na RPC",
          rpc_errors: cleanupResult?.error_count ?? 0,
          cleanup_result: cleanupResult
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log("Limpeza completa concluída com sucesso:", cleanupResult);

    return new Response(
      JSON.stringify({
        success: true,
        result: cleanupResult,
        timestamp: new Date().toISOString(),
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Erro inesperado:", error);
    return new Response(
      JSON.stringify({ error: "Erro inesperado", details: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});