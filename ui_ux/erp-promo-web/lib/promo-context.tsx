"use client";

import React, { createContext, useContext, useState, useEffect, useCallback } from "react";
import {
  CurrencyCode,
  DashboardOverviewData,
  LangCode,
  MenuPermissionFlags,
  MultiTenantUserContext,
  PromoItem,
  UserRole,
} from "./promo-types";

interface PromoContextValue {
  lang: LangCode;
  setLang: (lang: LangCode) => void;
  currency: CurrencyCode;
  setCurrency: (currency: CurrencyCode) => void;
  role: UserRole;
  activeUsername: string;
  setActiveUsername: (username: string) => void;
  selectedCompanyId: number | null;
  setSelectedCompanyId: (companyId: number | null) => void;
  userContext: MultiTenantUserContext | null;
  getMenuPermission: (menuCode: string) => MenuPermissionFlags;
  searchQuery: string;
  setSearchQuery: (q: string) => void;
  data: DashboardOverviewData | null;
  loading: boolean;
  error: string | null;
  selectedPromo: PromoItem | null;
  setSelectedPromo: (promo: PromoItem | null) => void;
  openPromoById: (id: string) => void;
  refreshData: () => Promise<void>;
  toastMsg: string | null;
  showToast: (msg: string) => void;
  openModalAction: (kind: "approve" | "reject" | "extend" | "request", promo: PromoItem) => void;
  modalState: {
    open: boolean;
    kind: "approve" | "reject" | "extend" | "request";
    promo: PromoItem | null;
  };
  closeModalAction: () => void;
}

const PromoContext = createContext<PromoContextValue | undefined>(undefined);

const DEFAULT_PERM: MenuPermissionFlags = {
  view: 1,
  add: 1,
  edit: 1,
  delete: 1,
  approve: 1,
};

const FALLBACK_OVERVIEW_DATA: DashboardOverviewData = {
  userContext: {
    userId: 8,
    username: "budi.santoso",
    fullName: "Budi Santoso",
    roleId: 1,
    roleName: "Super Admin",
    isSuperAdmin: true,
    userCompanyId: 1,
    effectiveCompanyId: 1,
    companyCode: "COMP01",
    companyName: "PT Maju Jaya",
    menus: [
      {
        menuId: 4001,
        menuCode: "PROMO-OVERVIEW",
        menuName: "Ringkasan Promo",
        menuLink: "/dashboard/overview",
        moduleId: 401,
        moduleName: "Promo Overview",
        applicationId: 4,
        applicationCode: "PROMO",
        applicationName: "Promotion System",
        permissions: DEFAULT_PERM,
      },
      {
        menuId: 4002,
        menuCode: "PROMO-LIST",
        menuName: "Daftar Promo",
        menuLink: "/dashboard/promos",
        moduleId: 402,
        moduleName: "Promotion Management",
        applicationId: 4,
        applicationCode: "PROMO",
        applicationName: "Promotion System",
        permissions: DEFAULT_PERM,
      },
      {
        menuId: 4003,
        menuCode: "PROMO-APPROVAL",
        menuName: "Approval Promo",
        menuLink: "/dashboard/approvals",
        moduleId: 403,
        moduleName: "Promo Approvals",
        applicationId: 4,
        applicationCode: "PROMO",
        applicationName: "Promotion System",
        permissions: DEFAULT_PERM,
      },
      {
        menuId: 4004,
        menuCode: "PROMO-SIMULATOR",
        menuName: "Simulator Promo",
        menuLink: "/dashboard/simulator",
        moduleId: 404,
        moduleName: "Rule Simulator",
        applicationId: 4,
        applicationCode: "PROMO",
        applicationName: "Promotion System",
        permissions: DEFAULT_PERM,
      },
      {
        menuId: 4005,
        menuCode: "PROMO-RETURN",
        menuName: "Retur Promo",
        menuLink: "/dashboard/returns",
        moduleId: 405,
        moduleName: "Promo Returns",
        applicationId: 4,
        applicationCode: "PROMO",
        applicationName: "Promotion System",
        permissions: DEFAULT_PERM,
      },
      {
        menuId: 4006,
        menuCode: "PROMO-AUDIT",
        menuName: "Audit Log Promo",
        menuLink: "/dashboard/audit",
        moduleId: 406,
        moduleName: "Promo Audit Log",
        applicationId: 4,
        applicationCode: "PROMO",
        applicationName: "Promotion System",
        permissions: DEFAULT_PERM,
      },
    ],
    promoPermissions: {
      "PROMO-OVERVIEW": DEFAULT_PERM,
      "PROMO-LIST": DEFAULT_PERM,
      "PROMO-APPROVAL": DEFAULT_PERM,
      "PROMO-SIMULATOR": DEFAULT_PERM,
      "PROMO-RETURN": DEFAULT_PERM,
      "PROMO-AUDIT": DEFAULT_PERM,
    },
    companies: [
      { companyId: 1, companyCode: "COMP01", companyName: "PT Maju Jaya" },
      { companyId: 2, companyCode: "COMP02", companyName: "CV Sukses Bersama" },
      { companyId: 3, companyCode: "COMP03", companyName: "PT Global Tech" },
    ],
    availableUsers: [
      {
        username: "budi.santoso",
        name: "Budi Santoso",
        companyId: 1,
        companyName: "PT Maju Jaya",
        roleName: "Super Admin",
      },
      {
        username: "andi.crm",
        name: "Andi CRM",
        companyId: 1,
        companyName: "PT Maju Jaya",
        roleName: "CRM User",
      },
      {
        username: "siti.acc",
        name: "Siti Akuntansi",
        companyId: 1,
        companyName: "PT Maju Jaya",
        roleName: "Accounting Admin",
      },
      {
        username: "dewi.hr",
        name: "Dewi HR",
        companyId: 3,
        companyName: "PT Global Tech",
        roleName: "HR Admin",
      },
    ],
  },
  kpi: {
    activePromos: 5,
    budgetUsedPercent: 52,
    totalBudgetCap: 550000000,
    totalBudgetUsed: 287500000,
    totalRedemptions: 11268,
    pendingApprovals: 1,
    expiringWithin7Days: 2,
  },
  trend14d: [420, 510, 480, 620, 790, 910, 1080, 940, 870, 990, 1180, 1340, 1290, 1480],
  promotions: [],
  returnEvents: [],
  auditLogs: [],
  fxRateUsdIdr: 16000,
};

export function PromoProvider({ children }: { children: React.ReactNode }) {
  const [lang, setLang] = useState<LangCode>("id");
  const [currency, setCurrency] = useState<CurrencyCode>("IDR");
  const [activeUsername, setActiveUsernameState] = useState<string>("budi.santoso");
  const [selectedCompanyId, setSelectedCompanyId] = useState<number | null>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [data, setData] = useState<DashboardOverviewData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedPromo, setSelectedPromo] = useState<PromoItem | null>(null);
  const [toastMsg, setToastMsg] = useState<string | null>(null);
  const [modalState, setModalState] = useState<{
    open: boolean;
    kind: "approve" | "reject" | "extend" | "request";
    promo: PromoItem | null;
  }>({
    open: false,
    kind: "approve",
    promo: null,
  });

  useEffect(() => {
    if (typeof window !== "undefined") {
      const urlUser = new URLSearchParams(window.location.search).get("username");
      const savedUser = urlUser || localStorage.getItem("erp_active_username");
      if (savedUser) {
        setActiveUsernameState(savedUser);
        localStorage.setItem("erp_active_username", savedUser);
      }
    }
  }, []);

  const setActiveUsername = useCallback((username: string) => {
    setActiveUsernameState(username);
    setSelectedCompanyId(null);
    if (typeof window !== "undefined") {
      localStorage.setItem("erp_active_username", username);
    }
  }, []);

  const showToast = useCallback((msg: string) => {
    setToastMsg(msg);
    setTimeout(() => {
      setToastMsg((prev: string | null) => (prev === msg ? null : prev));
    }, 2800);
  }, []);

  const refreshData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const qs = new URLSearchParams();
      if (activeUsername) qs.set("username", activeUsername);
      if (selectedCompanyId !== null) qs.set("companyId", String(selectedCompanyId));
      const res = await fetch(`/api/promo/overview?${qs.toString()}`, { cache: "no-store" });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      const json: DashboardOverviewData = await res.json();
      setData(json);
      if (selectedPromo) {
        const updated = json.promotions.find(
          (p: PromoItem) => p.code === selectedPromo.code || p.id === selectedPromo.id
        );
        setSelectedPromo(updated || null);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Gagal memuat data";
      setError(msg);
      if (!data) {
        setData(FALLBACK_OVERVIEW_DATA);
      }
    } finally {
      setLoading(false);
    }
  }, [activeUsername, selectedCompanyId, selectedPromo, data]);

  useEffect(() => {
    refreshData();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeUsername, selectedCompanyId]);

  const userContext = data?.userContext || null;

  const getMenuPermission = useCallback(
    (menuCode: string): MenuPermissionFlags => {
      if (!userContext) return DEFAULT_PERM;
      if (userContext.isSuperAdmin) return DEFAULT_PERM;
      return (
        userContext.promoPermissions?.[menuCode] || {
          view: 0,
          add: 0,
          edit: 0,
          delete: 0,
          approve: 0,
        }
      );
    },
    [userContext]
  );

  // Role ditentukan otomatis dari permission database (adm_mst_role_menu / adm_mst_user_menu)
  const role: UserRole =
    getMenuPermission("PROMO-APPROVAL").approve === 1 ? "checker" : "maker";

  const openPromoById = useCallback(
    (idOrCode: string) => {
      if (!data) return;
      const found = data.promotions.find(
        (p: PromoItem) => p.code === idOrCode || p.id === idOrCode
      );
      if (found) {
        setSelectedPromo(found);
      }
    },
    [data]
  );

  const openModalAction = useCallback(
    (kind: "approve" | "reject" | "extend" | "request", promo: PromoItem) => {
      setModalState({ open: true, kind, promo });
    },
    []
  );

  const closeModalAction = useCallback(() => {
    setModalState(
      (prev: {
        open: boolean;
        kind: "approve" | "reject" | "extend" | "request";
        promo: PromoItem | null;
      }) => ({ ...prev, open: false })
    );
  }, []);

  return (
    <PromoContext.Provider
      value={{
        lang,
        setLang,
        currency,
        setCurrency,
        role,
        activeUsername,
        setActiveUsername,
        selectedCompanyId,
        setSelectedCompanyId,
        userContext,
        getMenuPermission,
        searchQuery,
        setSearchQuery,
        data,
        loading,
        error,
        selectedPromo,
        setSelectedPromo,
        openPromoById,
        refreshData,
        toastMsg,
        showToast,
        openModalAction,
        modalState,
        closeModalAction,
      }}
    >
      {children}
    </PromoContext.Provider>
  );
}

export function usePromo() {
  const ctx = useContext(PromoContext);
  if (!ctx) {
    throw new Error("usePromo must be used inside PromoProvider");
  }
  return ctx;
}
