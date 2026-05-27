import { describe, it, expect } from "vitest";
import { compressImage, ACCEPTED_IMAGE_TYPES } from "./imageUpload";

describe("imageUpload validation", () => {
  it("rejects SVG files", async () => {
    const file = new File(["<svg/>"], "x.svg", { type: "image/svg+xml" });
    await expect(compressImage(file)).rejects.toThrow(/Unsupported file type/);
  });

  it("rejects PDFs and other docs", async () => {
    const file = new File(["%PDF-"], "x.pdf", { type: "application/pdf" });
    await expect(compressImage(file)).rejects.toThrow(/Unsupported file type/);
  });

  it("accepts PNG/JPG/WEBP MIME types", () => {
    expect(ACCEPTED_IMAGE_TYPES).toEqual(
      expect.arrayContaining(["image/png", "image/jpeg", "image/webp"])
    );
    expect(ACCEPTED_IMAGE_TYPES).not.toContain("image/svg+xml");
  });

  it("rejects oversized files", async () => {
    const big = new Uint8Array(6 * 1024 * 1024);
    const file = new File([big], "big.png", { type: "image/png" });
    await expect(compressImage(file)).rejects.toThrow(/5 MB/);
  });
});