"use client";

import React from "react";
import { usePromo } from "@/lib/promo-context";
import AuditView from "./audit-view";
import { buildUnifiedAuditTimeline } from "./audit.service";

export default function AuditPage() {
  const { lang, data, openPromoById } = usePromo();

  if (!data) {
    return <div style={{ color: "#6b7280" }}>Memuat audit log...</div>;
  }

  const entries = buildUnifiedAuditTimeline(data.promotions, data.auditLogs);

  return (
    <AuditView
      lang={lang}
      entries={entries}
      onOpenPromo={openPromoById}
    />
  );
}
