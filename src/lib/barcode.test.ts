import { describe, expect, it } from "vitest";
import { code128Modules, generateBatchCode, normalizeBarcodeToken, productCodeFromName } from "./barcode";

describe("barcode helpers", () => {
  it("normalizes scanned barcode tokens", () => {
    expect(normalizeBarcodeToken(" cb-btch-20260528-soy-1a2b ")).toBe("CB-BTCH-20260528-SOY-1A2B");
    expect(normalizeBarcodeToken("CB BTCH 20260528 SOY 1A2B")).toBe("CBBTCH20260528SOY1A2B");
  });

  it("builds compact product code fragments", () => {
    expect(productCodeFromName("Banana Ketchup")).toBe("BANKET");
    expect(productCodeFromName("Fish Sauce")).toBe("FISSAU");
  });

  it("generates token-only batch codes", () => {
    expect(generateBatchCode("Sweet Sauce", new Date("2026-05-28T00:00:00Z"), 0)).toBe("CB-BTCH-20260528-SWESAU-0000");
  });

  it("creates Code 128 module strings for printable ASCII", () => {
    expect(code128Modules("CB-BTCH-20260528-FISSAU-0001")).toMatch(/^[1-4]+$/);
  });
});
