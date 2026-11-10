import { DashboardOverviewData, PromoItem } from "@/lib/promo-types";

export interface StatusMixCounts {
  active: number;
  scheduled: number;
  pending: number;
  paused: number;
  expired: number;
}

export function computeStatusMix(promotions: PromoItem[]): StatusMixCounts {
  const counts: StatusMixCounts = {
    active: 0,
    scheduled: 0,
    pending: 0,
    paused: 0,
    expired: 0,
  };
  for (const p of promotions) {
    const s = p.status.toLowerCase();
    if (s === "active") counts.active++;
    else if (s === "scheduled") counts.scheduled++;
    else if (s === "pending") counts.pending++;
    else if (s === "paused" || s === "draft") counts.paused++;
    else counts.expired++;
  }
  return counts;
}

export function getBurnPromotions(promotions: PromoItem[]): PromoItem[] {
  return promotions
    .filter((p) => p.budgetCap > 0)
    .sort((a, b) => b.budgetUsed / b.budgetCap - a.budgetUsed / a.budgetCap)
    .slice(0, 6);
}

export function getTopRoiPromotions(promotions: PromoItem[]): PromoItem[] {
  return promotions
    .filter((p) => p.roi > 0)
    .sort((a, b) => b.roi - a.roi);
}

export async function fetchOverviewMetrics(): Promise<DashboardOverviewData> {
  const res = await fetch("/api/promo/overview", { cache: "no-store" });
  if (!res.ok) {
    throw new Error("Gagal mengambil data ringkasan promo");
  }
  return res.json();
}
