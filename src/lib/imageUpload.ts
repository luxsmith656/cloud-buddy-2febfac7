import { supabase } from "@/integrations/supabase/client";

export const ACCEPTED_IMAGE_TYPES = [
  "image/png",
  "image/jpeg",
  "image/jpg",
  "image/webp",
];

export const ACCEPT_ATTR = ACCEPTED_IMAGE_TYPES.join(",");

const MAX_FILE_SIZE = 5 * 1024 * 1024;
const MAX_DIMENSION = 1280;
const QUALITY = 0.7;

/** Validate and compress safe raster images to webp. */
export async function compressImage(file: File): Promise<File> {
  if (!ACCEPTED_IMAGE_TYPES.includes(file.type)) {
    throw new Error("Unsupported file type. Use PNG, JPG, or WEBP.");
  }

  if (file.size > MAX_FILE_SIZE) {
    throw new Error("Image must be 5 MB or smaller.");
  }

  const bitmap = await createImageBitmap(file).catch(() => null);
  if (!bitmap) return file;

  let { width, height } = bitmap;
  if (width > MAX_DIMENSION || height > MAX_DIMENSION) {
    const ratio = Math.min(MAX_DIMENSION / width, MAX_DIMENSION / height);
    width = Math.round(width * ratio);
    height = Math.round(height * ratio);
  }

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  if (!ctx) return file;
  ctx.drawImage(bitmap, 0, 0, width, height);

  const blob: Blob | null = await new Promise((resolve) =>
    canvas.toBlob(resolve, "image/webp", QUALITY)
  );
  if (!blob) return file;

  // If compression made it bigger, keep original
  if (blob.size >= file.size) return file;

  return new File([blob], file.name.replace(/\.[^.]+$/, "") + ".webp", {
    type: "image/webp",
  });
}

/** Validate + compress + upload. Returns the public URL. */
export async function uploadCompressedImage(
  file: File,
  folder: string
): Promise<string> {
  const compressed = await compressImage(file);
  const ext = compressed.name.split(".").pop() || "webp";
  const fileName = `${crypto.randomUUID()}.${ext}`;
  const filePath = `${folder}/${fileName}`;

  const { error } = await supabase.storage
    .from("images")
    .upload(filePath, compressed, {
      cacheControl: "3600",
      upsert: false,
      contentType: compressed.type,
    });
  if (error) throw error;

  const { data } = supabase.storage.from("images").getPublicUrl(filePath);
  return data.publicUrl;
}
