"use client";

import React from "react";
import { useRouter } from "next/navigation";
import { usePromo } from "@/lib/promo-context";
import OverviewView from "./overview-view";
import {
  computeStatusMix,
  getBurnPromotions,
  getTopRoiPromotions,
} from "./overview.service";

export default function OverviewPage() {
  const router = useRouter();
  const { lang, currency, data, setSelectedPromo } = usePromo();

  if (!data) {
    return <div style={{ color: "#6b7280" }}>Memuat ringkasan PromoHub...</div>;
  }

  const statusMix = computeStatusMix(data.promotions);
  const burnPromos = getBurnPromotions(data.promotions);
  const topRoiPromos = getTopRoiPromotions(data.promotions);

  return (
    <OverviewView
      lang={lang}
      currency={currency}
      data={data}
      statusMix={statusMix}
      burnPromos={burnPromos}
      topRoiPromos={topRoiPromos}
      onSelectPromo={setSelectedPromo}
      onNavigateApprovals={() => router.push("/dashboard/approvals")}
    />
  );
}
