import { PromoItem } from "@/lib/promo-types";

export function getPendingApprovals(promotions: PromoItem[]): PromoItem[] {
  return promotions.filter((p) => p.status.toLowerCase() === "pending");
}
