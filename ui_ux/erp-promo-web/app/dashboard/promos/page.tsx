"use client";

import React, { useState } from "react";
import { usePromo } from "@/lib/promo-context";
import { PromoStatus } from "@/lib/promo-types";
import PromosView from "./promos-view";
import {
  CreatePromoFormInput,
  createNewPromotion,
  filterPromotions,
} from "./promos.service";

export default function PromosPage() {
  const {
    lang,
    currency,
    activeUsername,
    selectedCompanyId,
    userContext,
    getMenuPermission,
    searchQuery,
    data,
    setSelectedPromo,
    refreshData,
    showToast,
  } = usePromo();

  const [statusFilter, setStatusFilter] = useState<PromoStatus>("all");
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [creating, setCreating] = useState(false);

  const [formInput, setFormInput] = useState<CreatePromoFormInput>({
    code: "P-110",
    name: "Promo Gajian Spesial 20%",
    promoTypeCode: "flash_sale",
    priority: 85,
    startAt: "2026-04-20",
    endAt: "2026-05-15",
    expiresAt: "2026-05-15",
    budgetCap: 50000000,
    redemptionCap: 2500,
    makerId: "Ayu (Merch)",
    benefitKind: "PERCENT",
    benefitValue: 20,
    minCartSubtotal: 150000,
  });

  if (!data) {
    return <div style={{ color: "#6b7280" }}>Memuat daftar promosi...</div>;
  }

  const canAddPromo = getMenuPermission("PROMO-LIST").add === 1;

  const filteredPromos = filterPromotions(
    data.promotions,
    statusFilter,
    searchQuery
  );

  const handleSubmitCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      setCreating(true);
      await createNewPromotion({
        ...formInput,
        makerId: userContext?.fullName || activeUsername,
        username: activeUsername,
        companyId: selectedCompanyId ?? userContext?.effectiveCompanyId ?? 1,
      });
      setShowCreateModal(false);
      await refreshData();
      showToast(`Promo ${formInput.code} berhasil dibuat ✓`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Gagal membuat promo";
      showToast(msg);
    } finally {
      setCreating(false);
    }
  };

  return (
    <PromosView
      lang={lang}
      currency={currency}
      rate={data.fxRateUsdIdr || 16000}
      statusFilter={statusFilter}
      onStatusFilterChange={setStatusFilter}
      totalCount={data.promotions.length}
      filteredPromos={filteredPromos}
      onSelectPromo={setSelectedPromo}
      canAddPromo={canAddPromo}
      showCreateModal={showCreateModal}
      onOpenCreateModal={() => setShowCreateModal(true)}
      onCloseCreateModal={() => setShowCreateModal(false)}
      formInput={formInput}
      onFormChange={setFormInput}
      onSubmitCreate={handleSubmitCreate}
      creating={creating}
    />
  );
}
