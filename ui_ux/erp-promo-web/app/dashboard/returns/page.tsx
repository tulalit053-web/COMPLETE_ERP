"use client";

import React, { useState } from "react";
import { usePromo } from "@/lib/promo-context";
import ReturnsView from "./returns-view";
import {
  evaluateOrCommitReturn,
  ReturnSimInput,
  ReturnSimOutput,
} from "./returns.service";

export default function ReturnsPage() {
  const {
    lang,
    currency,
    data,
    openPromoById,
    refreshData,
    showToast,
  } = usePromo();

  const [simInput, setSimInput] = useState<ReturnSimInput>({
    orderId: "ORD-91005",
    promoId: "P-101",
    returnType: "PARTIAL",
    reasonCode: "CUSTOMER_REMORSE",
    returnedQty: 1,
    unitPrice: 150000,
    allocatedDiscount: 50000,
  });
  const [simOutput, setSimOutput] = useState<ReturnSimOutput | null>(null);
  const [loadingSim, setLoadingSim] = useState(false);

  if (!data) {
    return <div style={{ color: "#6b7280" }}>Memuat data retur...</div>;
  }

  const handleSimulateReturn = async (mode: "evaluate" | "commit") => {
    try {
      setLoadingSim(true);
      const res = await evaluateOrCommitReturn(mode, simInput);
      setSimOutput(res);
      if (mode === "commit") {
        await refreshData();
        showToast(`Retur ${res.returnNo || simInput.orderId} berhasil disimpan ✓`);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Gagal memproses retur";
      showToast(msg);
    } finally {
      setLoadingSim(false);
    }
  };

  return (
    <ReturnsView
      lang={lang}
      currency={currency}
      rate={data.fxRateUsdIdr || 16000}
      returnEvents={data.returnEvents}
      onOpenPromo={openPromoById}
      simInput={simInput}
      onSimInputChange={setSimInput}
      onSimulateReturn={handleSimulateReturn}
      simOutput={simOutput}
      loadingSim={loadingSim}
    />
  );
}
