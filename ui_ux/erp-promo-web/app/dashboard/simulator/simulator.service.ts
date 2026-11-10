export interface SimulatorCartLine {
  lineId: string;
  sku: string;
  category: string;
  brand: string;
  qty: number;
  unitPrice: number;
}

export interface SimulatorEvaluatePayload {
  channel: string;
  currency: string;
  locale: string;
  customer: {
    id: string;
    tier: string;
    segments: string[];
    isNewUser: boolean;
    daysSinceLastPurchase: number;
  };
  cart: {
    lines: SimulatorCartLine[];
    shippingFee: number;
    vouchers: string[];
  };
  payment: {
    method: string;
    bin: string;
    issuer: string;
  };
}

export interface AppliedPromoDto {
  promoId: string;
  code: string;
  version: number;
  name: string;
  benefitKind: string;
  discountAmount: number;
  freeItems: Array<{ sku: string; qty: number; unitPrice: number }>;
  returnPolicyMode: string;
}

export interface RejectedPromoDto {
  promoId: string;
  code: string;
  reasonCode: string;
  message: string;
}

export interface LineDiscountAllocationDto {
  lineId: string;
  sku: string;
  qty: number;
  unitPrice: number;
  lineSubtotal: number;
  allocatedDiscount: number;
  netLineAmount: number;
}

export interface SimulatorEvaluateResult {
  currency: string;
  subtotal: number;
  shippingFee: number;
  totalDiscount: number;
  shippingDiscount: number;
  grandTotal: number;
  appliedPromos: AppliedPromoDto[];
  rejectedPromos: RejectedPromoDto[];
  lineAllocations: LineDiscountAllocationDto[];
}

export async function runCartSimulation(
  payload: SimulatorEvaluatePayload
): Promise<SimulatorEvaluateResult> {
  const response = await fetch("/api/promo/evaluate", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error || "Gagal menjalankan simulasi promo");
  }
  return data;
}
