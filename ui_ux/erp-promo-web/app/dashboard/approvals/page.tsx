"use client";

import React from "react";
import { usePromo } from "@/lib/promo-context";
import ApprovalsView from "./approvals-view";
import { getPendingApprovals } from "./approvals.service";

export default function ApprovalsPage() {
  const {
    lang,
    currency,
    role,
    data,
    setSelectedPromo,
    openModalAction,
  } = usePromo();

  if (!data) {
    return <div style={{ color: "#6b7280" }}>Memuat antrean approval...</div>;
  }

  const pendingPromos = getPendingApprovals(data.promotions);

  return (
    <ApprovalsView
      lang={lang}
      currency={currency}
      role={role}
      rate={data.fxRateUsdIdr || 16000}
      pendingPromos={pendingPromos}
      onSelectPromo={setSelectedPromo}
      onApprove={(p) => openModalAction("approve", p)}
      onReject={(p) => openModalAction("reject", p)}
    />
  );
}
