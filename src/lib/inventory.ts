import type { Enums, Tables } from "@/integrations/supabase/types";

export type ProductStatus = Enums<"product_status">;
export type StockMovement = Tables<"stock_movements">;

export const EXPIRING_SOON_DAYS = 7;

function localDateKey(value: Date): string {
  const year = value.getFullYear();
  const month = String(value.getMonth() + 1).padStart(2, "0");
  const day = String(value.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function computeProductStatus(
  quantity: number,
  minStock: number,
  expirationDate?: string | null,
  now: Date = new Date(),
): ProductStatus {
  if (quantity <= 0) return "out-of-stock";

  if (expirationDate) {
    const expiry = new Date(`${expirationDate}T00:00:00`);
    const today = new Date(now);
    today.setHours(0, 0, 0, 0);
    const daysUntilExpiry = Math.ceil((expiry.getTime() - today.getTime()) / 86_400_000);
    if (daysUntilExpiry <= EXPIRING_SOON_DAYS) return "expiring";
  }

  if (quantity <= minStock) return "low-stock";

  return "in-stock";
}

export function buildWeeklyMovementTrend(
  movements: Pick<StockMovement, "created_at" | "type" | "quantity">[],
  now: Date = new Date(),
) {
  const formatter = new Intl.DateTimeFormat("en-US", { weekday: "short" });
  const days = Array.from({ length: 7 }, (_, index) => {
    const date = new Date(now);
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() - (6 - index));
    return {
      key: localDateKey(date),
      day: formatter.format(date).toUpperCase(),
      stockIn: 0,
      stockOut: 0,
    };
  });
  const dayMap = new Map(days.map((day) => [day.key, day]));

  for (const movement of movements) {
    const key = localDateKey(new Date(movement.created_at));
    const day = dayMap.get(key);
    if (!day) continue;

    if (movement.type === "IN") {
      day.stockIn += Math.abs(Number(movement.quantity));
    } else if (movement.type === "OUT") {
      day.stockOut += Math.abs(Number(movement.quantity));
    }
  }

  return days.map(({ key: _key, ...day }) => day);
}
