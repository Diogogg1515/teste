"use client";

import { useActionState, useEffect, useRef, useState } from "react";
import { addRecord, type RecordFormState } from "./actions";

const initialState: RecordFormState = { error: null, savedAt: null };

const ACCEPTED_TYPES = ["image/jpeg", "image/png", "image/webp"];
const MAX_ORIGINAL_BYTES = 20 * 1024 * 1024; // foto original: até 20 MB
const MAX_SIDE = 1600; // maior lado da foto depois de reduzida, em pixels
const TARGET_BYTES = 900 * 1024; // fotos menores que isso não são mexidas
const FALLBACK_MAX_BYTES = 3 * 1024 * 1024; // se não der para reduzir

// Reduz a foto no próprio celular antes de enviar: sai bem menor e passa
// fácil pelo limite de tamanho do servidor.
async function shrinkImage(file: File): Promise<File> {
  if (file.size <= TARGET_BYTES) {
    return file;
  }

  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, MAX_SIDE / Math.max(bitmap.width, bitmap.height));
  const width = Math.round(bitmap.width * scale);
  const height = Math.round(bitmap.height * scale);

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  if (!context) {
    throw new Error("Sem suporte a canvas.");
  }
  context.drawImage(bitmap, 0, 0, width, height);
  bitmap.close();

  const blob = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob(resolve, "image/jpeg", 0.82),
  );
  if (!blob) {
    throw new Error("Não foi possível reduzir a foto.");
  }

  const baseName = file.name.replace(/\.[^.]+$/, "") || "foto";
  return new File([blob], `${baseName}.jpg`, { type: "image/jpeg" });
}

// O campo de arquivo fica SEMPRE na tela (escondido): se ele sumisse depois
// de escolher a foto, o formulário enviaria o registro sem a foto.
function PhotoPicker({ onBusyChange }: { onBusyChange: (busy: boolean) => void }) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // Libera a memória da pré-visualização
  useEffect(() => {
    return () => {
      if (preview) URL.revokeObjectURL(preview);
    };
  }, [preview]);

  function clear() {
    if (inputRef.current) inputRef.current.value = "";
    setPreview(null);
  }

  async function handleChange(event: React.ChangeEvent<HTMLInputElement>) {
    const input = event.currentTarget;
    const original = input.files?.[0];
    setMessage(null);

    if (!original) {
      clear();
      return;
    }

    if (!ACCEPTED_TYPES.includes(original.type)) {
      clear();
      setMessage(
        "Formato não aceito. Use foto JPG, PNG ou WEBP. No iPhone: Ajustes > Câmera > Formatos > Mais compatível.",
      );
      return;
    }
    if (original.size > MAX_ORIGINAL_BYTES) {
      clear();
      setMessage("A foto é muito grande (máximo 20 MB).");
      return;
    }

    setBusy(true);
    onBusyChange(true);
    try {
      let ready: File;
      try {
        ready = await shrinkImage(original);
      } catch {
        // Não deu para reduzir: só segue se a foto original já for pequena.
        if (original.size > FALLBACK_MAX_BYTES) {
          clear();
          setMessage("Não foi possível preparar a foto. Tente outra foto.");
          return;
        }
        ready = original;
      }

      // Troca o arquivo do campo pela versão reduzida
      const transfer = new DataTransfer();
      transfer.items.add(ready);
      input.files = transfer.files;
      setPreview(URL.createObjectURL(ready));
    } finally {
      setBusy(false);
      onBusyChange(false);
    }
  }

  return (
    <div className="flex flex-col gap-3">
      <input
        ref={inputRef}
        id="photo"
        name="file"
        type="file"
        accept="image/jpeg,image/png,image/webp"
        onChange={handleChange}
        className="sr-only"
      />

      {!preview && (
        <label
          htmlFor="photo"
          className="flex h-12 cursor-pointer items-center justify-center rounded-lg border border-gray-300 text-base font-medium"
        >
          {busy ? "Preparando a foto..." : "Anexar foto (opcional)"}
        </label>
      )}

      {preview && (
        <div className="flex flex-col gap-3 rounded-xl border border-gray-200 p-3">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={preview}
            alt="Pré-visualização da foto escolhida"
            className="max-h-64 w-full rounded-lg object-contain"
          />
          <label htmlFor="caption" className="text-sm font-medium">
            Legenda da foto (opcional)
          </label>
          <input
            id="caption"
            name="caption"
            type="text"
            maxLength={300}
            className="h-12 rounded-lg border border-gray-300 px-3 text-base text-gray-900"
          />
          <button
            type="button"
            onClick={clear}
            className="h-10 rounded-lg border border-gray-300 text-sm font-medium"
          >
            Remover foto
          </button>
        </div>
      )}

      {message && (
        <p role="alert" className="text-sm text-red-600">
          {message}
        </p>
      )}
    </div>
  );
}

export function RecordForm({
  serviceId,
  role,
}: {
  serviceId: string;
  role: "client" | "worker";
}) {
  const [state, formAction, pending] = useActionState(addRecord, initialState);
  const [photoBusy, setPhotoBusy] = useState(false);

  const placeholder =
    role === "client"
      ? "Conte o que aconteceu, como ficou o serviço ou o que você observou."
      : "Registre o problema identificado, o que foi feito, materiais e observações.";

  // O envio é feito aqui (e não pelo "action" do formulário) para o React
  // não limpar o texto e a foto quando houver um erro.
  function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    formAction(data);
  }

  return (
    // A chave muda depois de salvar: tudo volta vazio (texto e foto).
    <form
      key={state.savedAt ?? "novo"}
      onSubmit={handleSubmit}
      className="flex flex-col gap-3"
    >
      <input type="hidden" name="service_id" value={serviceId} />

      <label htmlFor="content" className="text-sm font-medium">
        Novo registro
      </label>
      <textarea
        id="content"
        name="content"
        rows={4}
        required
        maxLength={5000}
        placeholder={placeholder}
        className="rounded-lg border border-gray-300 px-3 py-2 text-base text-gray-900"
      />

      <PhotoPicker onBusyChange={setPhotoBusy} />

      {state.error && (
        <p role="alert" className="text-sm text-red-600">
          {state.error}
        </p>
      )}
      {state.savedAt && !state.error && (
        <p role="status" className="text-sm text-green-700">
          Registro salvo.
        </p>
      )}

      <button
        type="submit"
        disabled={pending || photoBusy}
        className="h-12 rounded-lg bg-gray-900 text-base font-medium text-white disabled:opacity-60"
      >
        {pending ? "Salvando..." : "Adicionar registro"}
      </button>
    </form>
  );
}