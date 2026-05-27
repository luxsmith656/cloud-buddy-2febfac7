import { describe, expect, it } from "vitest";
import { buildWeeklyMovementTrend, computeProductStatus } from "./inventory";

describe("computeProductStatus", () => {
  it("prioritizes out-of-stock before other statuses", () => {
    expect(computeProductStatus(0, 10, "2026-05-28", new Date("2026-05-27"))).toBe("out-of-stock");
  });

  it("marks products expiring within seven days", () => {
    expect(computeProductStatus(20, 10, "2026-06-02", new Date("2026-05-27"))).toBe("expiring");
  });

  it("marks products at or below minimum stock as low stock", () => {
    expect(computeProductStatus(10, 10, null, new Date("2026-05-27"))).toBe("low-stock");
  });
});

describe("buildWeeklyMovementTrend", () => {
  it("summarizes stock in and out for the last seven days", () => {
    const trend = buildWeeklyMovementTrend(
      [
        { created_at: "2026-05-27T10:00:00Z", type: "IN", quantity: 5 },
        { created_at: "2026-05-27T12:00:00Z", type: "OUT", quantity: -2 },
      ],
      new Date("2026-05-27T13:00:00Z"),
    );

    expect(trend[trend.length - 1]).toMatchObject({ stockIn: 5, stockOut: 2 });
  });
});
