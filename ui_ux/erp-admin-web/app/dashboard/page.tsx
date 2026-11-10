"use client";

import { useEffect, useState } from "react";
import DashboardView from "./dashboard-view";
import { AdminSessionContext, fetchPortalContext } from "./dashboard.service";

const PROMO_WEB_URL =
  process.env.NEXT_PUBLIC_PROMO_WEB_URL || "http://localhost:3001";

export default function DashboardPage() {
  const [session, setSession] = useState<AdminSessionContext | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [selectedCompanyId, setSelectedCompanyId] = useState<number | null>(null);

  const loadContext = async (targetUser?: string, companyId?: number | null) => {
    setLoading(true);
    setError("");
    try {
      const savedUser =
        targetUser ||
        localStorage.getItem("erp_active_username") ||
        "budi.santoso";
      localStorage.setItem("erp_active_username", savedUser);
      const data = await fetchPortalContext(savedUser, companyId);
      setSession(data);
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Gagal memuat konteks sesi"
      );
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadContext();
  }, []);

  const handleSwitchUser = (username: string) => {
    setSelectedCompanyId(null);
    loadContext(username, null);
  };

  const handleSwitchCompany = (companyId: number | null) => {
    setSelectedCompanyId(companyId);
    loadContext(session?.username, companyId);
  };

  const handleLogout = () => {
    localStorage.removeItem("erp_active_username");
    window.location.href = "/login";
  };

  return (
    <DashboardView
      session={session}
      loading={loading}
      error={error}
      promoWebUrl={PROMO_WEB_URL}
      selectedCompanyId={selectedCompanyId}
      onSwitchCompany={handleSwitchCompany}
      onLogout={handleLogout}
    />
  );
}
