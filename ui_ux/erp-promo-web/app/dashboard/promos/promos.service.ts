import { PromoItem, PromoStatus } from "@/lib/promo-types";

export interface CreatePromoFormInput {
  code: string;
  name: string;
  promoTypeCode: string;
  priority: number;
  startAt: string;
  endAt: string;
  expiresAt: string;
  budgetCap: number;
  redemptionCap: number;
  makerId: string;
  benefitKind: "PERCENT" | "FIXED_AMOUNT" | "FREE_SHIPPING";
  benefitValue: number;
  minCartSubtotal: number;
  username?: string;
  companyId?: number | null;
}

export function filterPromotions(
  promotions: PromoItem[],
  statusFilter: PromoStatus,
  searchQuery: string
): PromoItem[] {
  const q = searchQuery.trim().toLowerCase();
  return promotions.filter((p) => {
    const matchStatus =
      statusFilter === "all" || p.status.toLowerCase() === statusFilter;
    const matchQuery =
      !q ||
      p.code.toLowerCase().includes(q) ||
      p.name.toLowerCase().includes(q) ||
      (p.localizedNames?.id || "").toLowerCase().includes(q) ||
      (p.localizedNames?.en || "").toLowerCase().includes(q);
    return matchStatus && matchQuery;
  });
}

export async function createNewPromotion(input: CreatePromoFormInput) {
  const configPayload = {
    version: 1,
    conditions: {
      op: "AND",
      rules:
        input.minCartSubtotal > 0
          ? [{ fact: "cart.subtotal", op: "GTE", value: input.minCartSubtotal }]
          : [],
    },
    benefits: [
      {
        kind: input.benefitKind,
        value: input.benefitValue,
        target: input.benefitKind === "FREE_SHIPPING" ? "SHIPPING" : "CART",
      },
    ],
    limits: {
      budget_cap: { amount: input.budgetCap, currency: "IDR" },
      quota_total: input.redemptionCap,
    },
    funding: {
      id: "100% Merchant",
      en: "100% Merchant",
    },
    return_policy: {
      id: "PRORATE — Potong refund sesuai diskon item",
      en: "PRORATE — Deduct refund by prorated discount",
    },
    summary: {
      id: `${input.name} (Min. belanja Rp${input.minCartSubtotal.toLocaleString("id-ID")})`,
      en: `${input.name} (Min. spend IDR ${input.minCartSubtotal.toLocaleString("en-US")})`,
    },
  };

  const response = await fetch("/api/promo/promos", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      code: input.code,
      name: input.name,
      promoTypeCode: input.promoTypeCode,
      priority: input.priority,
      startAt: input.startAt,
      endAt: input.endAt,
      expiresAt: input.expiresAt,
      baseCurrency: "IDR",
      makerId: input.makerId,
      budgetCap: input.budgetCap,
      redemptionCap: input.redemptionCap,
      username: input.username,
      companyId: input.companyId,
      config: configPayload,
    }),
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error || "Gagal membuat promosi baru");
  }
  return data;
}
