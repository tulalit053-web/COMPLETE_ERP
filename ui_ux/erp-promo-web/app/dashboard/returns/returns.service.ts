export interface ReturnSimInput {
  orderId: string;
  promoId: string;
  returnType: "PARTIAL" | "FULL" | "EXCHANGE";
  reasonCode: "CUSTOMER_REMORSE" | "DEFECT" | "OUT_OF_STOCK" | "MERCHANT_FAULT";
  returnedQty: number;
  unitPrice: number;
  allocatedDiscount: number;
}

export interface ReturnSimOutput {
  returnNo?: string;
  orderId: string;
  grossRefund: number;
  discountClawback: number;
  netRefund: number;
  policyApplied: string;
  explanation: string;
}

export async function evaluateOrCommitReturn(
  mode: "evaluate" | "commit",
  input: ReturnSimInput
): Promise<ReturnSimOutput> {
  const response = await fetch("/api/promo/returns", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      mode,
      orderId: input.orderId,
      promoId: input.promoId,
      returnType: input.returnType,
      reasonCode: input.reasonCode,
      currency: "IDR",
      returnedLines: [
        {
          lineId: "L1",
          sku: "SKU-TEE-01",
          returnedQty: input.returnedQty,
          originalQty: input.returnedQty + 1,
          unitPrice: input.unitPrice,
          allocatedDiscount: input.allocatedDiscount,
        },
      ],
    }),
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error || "Gagal memproses evaluasi retur");
  }
  return data;
}
