"use client";

import { useEffect, useState, useCallback } from "react";
import { createPortal } from "react-dom";

type Photo = {
  id: string;
  url: string;
  caption: string;
  originalName: string;
};

type Props = {
  photos: Photo[];
  initialIndex: number;
  onClose: () => void;
};

export function Lightbox({ photos, initialIndex, onClose }: Props) {
  const [currentIndex, setCurrentIndex] = useState(initialIndex);
  const [mounted] = useState(true);

  const handlePrev = useCallback(() => {
    setCurrentIndex((prev) => (prev > 0 ? prev - 1 : photos.length - 1));
  }, [photos.length]);

  const handleNext = useCallback(() => {
    setCurrentIndex((prev) => (prev < photos.length - 1 ? prev + 1 : 0));
  }, [photos.length]);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
      if (e.key === "ArrowLeft") handlePrev();
      if (e.key === "ArrowRight") handleNext();
    };

    document.addEventListener("keydown", handleKeyDown);
    document.body.style.overflow = "hidden";

    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = "";
    };
  }, [currentIndex, onClose, handlePrev, handleNext]);

  const currentPhoto = photos[currentIndex];

  if (!mounted) return null;

  return createPortal(
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/95"
      onClick={onClose}
    >
      {/* Botão fechar */}
      <button
        onClick={onClose}
        className="absolute right-4 top-4 z-10 flex h-12 w-12 items-center justify-center rounded-full bg-white/10 text-white hover:bg-white/20"
        aria-label="Fechar"
      >
        <span className="text-2xl">×</span>
      </button>

      {/* Navegação anterior */}
      {photos.length > 1 && (
        <button
          onClick={(e) => {
            e.stopPropagation();
            handlePrev();
          }}
          className="absolute left-4 z-10 flex h-12 w-12 items-center justify-center rounded-full bg-white/10 text-white hover:bg-white/20"
          aria-label="Foto anterior"
        >
          <span className="text-2xl">‹</span>
        </button>
      )}

      {/* Imagem */}
      <div
        className="relative flex max-h-[90vh] max-w-[90vw] flex-col items-center gap-4"
        onClick={(e) => e.stopPropagation()}
      >
        <img
          src={currentPhoto.url}
          alt={currentPhoto.originalName}
          className="max-h-[80vh] max-w-full rounded-lg object-contain"
        />

        {/* Legenda */}
        {currentPhoto.caption && (
          <p className="max-w-2xl rounded-lg bg-white/10 px-4 py-2 text-center text-sm text-white">
            {currentPhoto.caption}
          </p>
        )}

        {/* Contador */}
        {photos.length > 1 && (
          <p className="text-sm text-white/70">
            {currentIndex + 1} / {photos.length}
          </p>
        )}
      </div>

      {/* Navegação próxima */}
      {photos.length > 1 && (
        <button
          onClick={(e) => {
            e.stopPropagation();
            handleNext();
          }}
          className="absolute right-4 z-10 flex h-12 w-12 items-center justify-center rounded-full bg-white/10 text-white hover:bg-white/20"
          aria-label="Próxima foto"
        >
          <span className="text-2xl">›</span>
        </button>
      )}
    </div>,
    document.body
  );
}
