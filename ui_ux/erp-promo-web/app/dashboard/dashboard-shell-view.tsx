"use client";

import React, { useState, useEffect, useMemo } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { usePromo } from "@/lib/promo-context";
import {
  formatDateShort,
  formatMoney,
  PromoItem,
  tr,
  UserMenuItem,
} from "@/lib/promo-types";
import {
  executePromoGovernanceAction,
  logoutFromSession,
} from "./dashboard.service";
import styles from "./DashboardShell.module.css";

function getStatusPillClass(status: string): string {
  switch (status.toLowerCase()) {
    case "active":
      return styles.pActive;
    case "scheduled":
      return styles.pScheduled;
    case "pending":
      return styles.pPending;
    case "paused":
    case "draft":
      return styles.pPaused;
    default:
      return styles.pExpired;
  }
}

export default function DashboardShellView({
  children,
}: {
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const {
    lang,
    setLang,
    currency,
    setCurrency,
    activeUsername,
    setActiveUsername,
    selectedCompanyId,
    setSelectedCompanyId,
    userContext,
    getMenuPermission,
    searchQuery,
    setSearchQuery,
    data,
    selectedPromo,
    setSelectedPromo,
    refreshData,
    toastMsg,
    showToast,
    modalState,
    openModalAction,
    closeModalAction,
  } = usePromo();

  const [reason, setReason] = useState("");
  const [newExpiresAt, setNewExpiresAt] = useState("");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (modalState.open && modalState.promo) {
      setReason("");
      const baseDate = new Date(
        (modalState.promo.expiresAt || "2026-04-30").slice(0, 10) + "T00:00:00Z"
      );
      baseDate.setUTCDate(baseDate.getUTCDate() + 14);
      setNewExpiresAt(baseDate.toISOString().slice(0, 10));
    }
  }, [modalState]);

  const pendingCount =
    data?.promotions.filter((p) => p.status === "pending").length ?? 0;

  const activeNavKey = pathname.includes("/promos")
    ? "promos"
    : pathname.includes("/approvals")
    ? "appr"
    : pathname.includes("/simulator")
    ? "sim"
    : pathname.includes("/returns")
    ? "ret"
    : pathname.includes("/audit")
    ? "aud"
    : "overview";

  const activeMenuCode = pathname.includes("/promos")
    ? "PROMO-LIST"
    : pathname.includes("/approvals")
    ? "PROMO-APPROVAL"
    : pathname.includes("/simulator")
    ? "PROMO-SIMULATOR"
    : pathname.includes("/returns")
    ? "PROMO-RETURN"
    : pathname.includes("/audit")
    ? "PROMO-AUDIT"
    : "PROMO-OVERVIEW";

  const currentMenuPerm = getMenuPermission(activeMenuCode);
  const canApprovePromo = getMenuPermission("PROMO-APPROVAL").approve === 1;
  const canEditPromo = getMenuPermission("PROMO-LIST").edit === 1;

  // Kelompokkan menu dinamis berdasarkan Application (PROMO, ACC, CRM, HRD)
  const groupedMenus = useMemo(() => {
    const menus = userContext?.menus || [];
    const groups: Record<string, { appName: string; items: UserMenuItem[] }> = {};

    // Urutkan agar Promotion System tampil paling atas di PromoHub
    const sorted = [...menus].sort((a, b) => {
      const aIsPromo = a.applicationCode === "PROMO" ? 0 : 1;
      const bIsPromo = b.applicationCode === "PROMO" ? 0 : 1;
      if (aIsPromo !== bIsPromo) return aIsPromo - bIsPromo;
      return (a.menuIndex || 99) - (b.menuIndex || 99);
    });

    for (const m of sorted) {
      const code = m.applicationCode || "APP";
      if (!groups[code]) {
        groups[code] = {
          appName: m.applicationName || code,
          items: [],
        };
      }
      groups[code].items.push(m);
    }
    return groups;
  }, [userContext]);

  const handleConfirmModal = async () => {
    if (!modalState.promo) return;
    if (!reason.trim()) {
      showToast(tr("bad", lang));
      return;
    }

    try {
      setSubmitting(true);
      const actor = userContext?.fullName || activeUsername;
      const actionMap: Record<
        "approve" | "reject" | "extend" | "request",
        "approve" | "reject" | "extend" | "submit"
      > = {
        approve: "approve",
        reject: "reject",
        extend: "extend",
        request: "submit",
      };

      await executePromoGovernanceAction(modalState.promo.id || modalState.promo.code, {
        action: actionMap[modalState.kind],
        actor,
        username: activeUsername,
        reason: reason.trim(),
        newExpiresAt: modalState.kind === "extend" ? newExpiresAt : undefined,
      });

      closeModalAction();
      await refreshData();
      showToast(`${modalState.promo.code} ✓`);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Gagal memproses aksi";
      showToast(msg);
    } finally {
      setSubmitting(false);
    }
  };

  const handleLogout = async () => {
    await logoutFromSession();
    router.push("/login");
  };

  const renderDrawerDetails = (p: PromoItem) => {
    const rate = data?.fxRateUsdIdr || 16000;
    const promoTitle = p.localizedNames?.[lang] || p.name;
    const cfg = (p.config || {}) as Record<string, unknown>;
    const summaryObj = (cfg.summary as Record<string, string>) || {};
    const detailObj = (cfg.detail as Record<string, string>) || {};
    const fundingObj = (cfg.funding as Record<string, string>) || {};
    const retPolObj = (cfg.return_policy as Record<string, string>) || {};

    return (
      <div
        className={styles.drawerBg}
        onClick={(e) => {
          if (e.target === e.currentTarget) setSelectedPromo(null);
        }}
      >
        <div className={styles.drawer}>
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              alignItems: "flex-start",
              gap: 12,
            }}
          >
            <div>
              <div style={{ display: "flex", gap: 6, alignItems: "center", marginBottom: 4 }}>
                <span className={styles.mono} style={{ color: "#6b7280" }}>
                  {p.code} · v{p.version} · {p.companyCode || `COMP0${p.companyId || 1}`}
                </span>
                <span className={`${styles.pill} ${getStatusPillClass(p.status)}`}>
                  <span className={styles.dot} />
                  {tr(p.status, lang)}
                </span>
                <span className={styles.tag}>{tr(p.type, lang)}</span>
              </div>
              <div style={{ fontSize: 16, fontWeight: 600 }}>{promoTitle}</div>
            </div>
            <button className={styles.btn} onClick={() => setSelectedPromo(null)}>
              ✕
            </button>
          </div>

          <div>
            <div className={styles.secTitle}>{tr("sum", lang)}</div>
            <div style={{ fontSize: 13.5, marginBottom: 6 }}>
              {summaryObj[lang] || p.description || promoTitle}
            </div>
            {detailObj[lang] && (
              <div className={styles.mono} style={{ color: "#6b7280" }}>
                {detailObj[lang]}
              </div>
            )}
          </div>

          <div>
            <div className={styles.secTitle}>{tr("lim", lang)}</div>
            <div className={styles.kv}>
              <div className={styles.kvKey}>{tr("period", lang)}</div>
              <div>
                {formatDateShort(p.startAt, lang)} – {formatDateShort(p.endAt, lang)}
              </div>
              <div className={styles.kvKey}>{tr("exp", lang)}</div>
              <div>
                <strong>{formatDateShort(p.expiresAt, lang)}</strong>
              </div>
              <div className={styles.kvKey}>{tr("budget", lang)}</div>
              <div>
                {formatMoney(p.budgetUsed, currency, lang, rate)} /{" "}
                {formatMoney(p.budgetCap, currency, lang, rate)}
              </div>
              <div className={styles.kvKey}>{tr("red", lang)}</div>
              <div>
                {p.redemptionUsed.toLocaleString()} / {p.redemptionCap.toLocaleString()}
              </div>
              <div className={styles.kvKey}>{tr("rr", lang)}</div>
              <div>
                {p.returnRate}% · {tr("roi", lang)} {p.roi ? `${p.roi}x` : "—"}
              </div>
            </div>
          </div>

          <div>
            <div className={styles.secTitle}>{tr("fund", lang)}</div>
            <div>{fundingObj[lang] || "100% Merchant"}</div>
            <div className={styles.secTitle} style={{ marginTop: 12 }}>
              {tr("rp", lang)}
            </div>
            <div>{retPolObj[lang] || "PRORATE — Potong refund sesuai diskon item"}</div>
          </div>

          <div>
            <div className={styles.secTitle}>{tr("hist", lang)}</div>
            <div
              style={{
                fontSize: 12.5,
                color: "#6b7280",
                marginBottom: 8,
              }}
            >
              {tr("mk", lang)}: <strong style={{ color: "#111827" }}>{p.makerId}</strong> ·{" "}
              {tr("ck", lang)}: <strong style={{ color: "#111827" }}>{p.checkerId || "—"}</strong>
            </div>
            <div className={styles.tl}>
              {(p.history || []).map((h, idx) => (
                <div key={idx} className={styles.tlItem}>
                  <div>
                    <strong>{h.actor}</strong> · {tr(h.action, lang)}{" "}
                    <span style={{ color: "#6b7280" }}>
                      ({formatDateShort(h.date, lang)})
                    </span>
                  </div>
                  {h.note && <div style={{ color: "#6b7280" }}>{h.note}</div>}
                </div>
              ))}
            </div>
          </div>

          <div
            style={{
              display: "flex",
              gap: 8,
              flexWrap: "wrap",
              paddingTop: 10,
              borderTop: "1px solid #e6e8ee",
            }}
          >
            {canApprovePromo && p.status === "pending" && (
              <>
                <button
                  className={`${styles.btn} ${styles.btnOk}`}
                  onClick={() => openModalAction("approve", p)}
                >
                  {tr("approve", lang)}
                </button>
                <button
                  className={`${styles.btn} ${styles.btnBad}`}
                  onClick={() => openModalAction("reject", p)}
                >
                  {tr("reject", lang)}
                </button>
              </>
            )}
            {canApprovePromo && (
              <button
                className={`${styles.btn} ${styles.btnPri}`}
                onClick={() => openModalAction("extend", p)}
              >
                {tr("ext", lang)}
              </button>
            )}
            {!canApprovePromo && canEditPromo && (
              <>
                <button
                  className={`${styles.btn} ${styles.btnPri}`}
                  onClick={() => openModalAction("request", p)}
                >
                  {tr("req", lang)}
                </button>
                <div style={{ fontSize: 12, color: "#6b7280", width: "100%" }}>
                  {tr("mkNote", lang)}
                </div>
              </>
            )}
            {!canApprovePromo && !canEditPromo && (
              <div style={{ fontSize: 12, color: "#6b7280", width: "100%" }}>
                Mode Baca Saja (Role {userContext?.roleName} hanya memiliki hak VIEW).
              </div>
            )}
          </div>
        </div>
      </div>
    );
  };

  return (
    <div className={styles.shell}>
      <aside className={styles.side}>
        <div className={styles.brand}>
          <div className={styles.logo}>P</div>
          <div>
            <div>ERP Portal</div>
            <div style={{ fontSize: 11, color: "#6b7280", fontWeight: 400 }}>
              Multi-Tenant &amp; RBAC
            </div>
          </div>
        </div>

        {userContext && (
          <div className={styles.tenantCard}>
            <div style={{ fontWeight: 600, color: "#111827" }}>
              {userContext.fullName}
            </div>
            <div style={{ color: "#4f46e5", fontWeight: 600 }}>
              {userContext.roleName}
            </div>
            <div style={{ color: "#6b7280", fontSize: 11.5 }}>
              Tenant: <strong>{userContext.companyName}</strong> ({userContext.companyCode})
            </div>
          </div>
        )}

        <nav className={styles.nav}>
          {Object.entries(groupedMenus).map(([appCode, group]) => (
            <div key={appCode} style={{ marginBottom: 8 }}>
              <div className={styles.appGroupTitle}>
                {group.appName} ({appCode})
              </div>
              {group.items.map((m) => {
                const isPromoLink = m.menuLink.startsWith("/dashboard/");
                const isActive = pathname === m.menuLink;
                const isApprovalMenu = m.menuCode === "PROMO-APPROVAL";
                return (
                  <Link
                    key={m.menuId}
                    href={isPromoLink ? m.menuLink : "#"}
                    onClick={(e) => {
                      if (!isPromoLink) {
                        e.preventDefault();
                        showToast(
                          `Modul [${appCode}] ${m.menuName} (${m.menuLink}) berada di microservice ${group.appName}`
                        );
                      }
                    }}
                    className={`${styles.navBtn} ${
                      isActive ? styles.navBtnActive : ""
                    }`}
                  >
                    <span>{m.menuName}</span>
                    {isApprovalMenu && pendingCount > 0 ? (
                      <span className={styles.badgeCount}>{pendingCount}</span>
                    ) : (
                      <span className={styles.permPills} title="Hak Akses (V=View, A=Add, E=Edit, P=Approve)">
                        {m.permissions?.view === 1 && <span className={styles.permMini}>V</span>}
                        {m.permissions?.add === 1 && <span className={styles.permMini}>A</span>}
                        {m.permissions?.approve === 1 && (
                          <span className={styles.permMini} style={{ color: "#059669" }}>
                            P
                          </span>
                        )}
                      </span>
                    )}
                  </Link>
                );
              })}
            </div>
          ))}
        </nav>

        <div className={styles.sideFoot}>
          <div>
            Engine v1.1 · FX 1 USD ={" "}
            {(data?.fxRateUsdIdr || 16000).toLocaleString("id-ID")} IDR
          </div>
          <button className={styles.logoutBtn} onClick={handleLogout}>
            Keluar / Logout
          </button>
        </div>
      </aside>

      <div className={styles.main}>
        <header className={styles.top}>
          <div>
            <div className={styles.title}>{tr(activeNavKey, lang)}</div>
            <div className={styles.sub}>{tr("sub", lang)}</div>
          </div>
          <div className={styles.spacer} />
          <div className={styles.ctrl}>
            <input
              type="text"
              className={styles.search}
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder={tr("search", lang)}
            />

            {/* Simulasi User Login dari adm_mst_user_application */}
            {userContext?.availableUsers && userContext.availableUsers.length > 0 && (
              <select
                className={styles.selectBox}
                value={activeUsername}
                onChange={(e) => setActiveUsername(e.target.value)}
                title="Simulasi Akun User (schema_admin.adm_mst_user_application)"
              >
                {userContext.availableUsers.map((u) => (
                  <option key={u.username} value={u.username}>
                    User: {u.name} ({u.roleName} - {u.companyName})
                  </option>
                ))}
              </select>
            )}

            {/* Filter Perusahaan Khusus Global Super Admin */}
            {userContext?.isSuperAdmin && (
              <select
                className={styles.selectBox}
                value={selectedCompanyId ?? 0}
                onChange={(e) => {
                  const val = Number(e.target.value);
                  setSelectedCompanyId(val > 0 ? val : null);
                }}
                title="Filter Multi-Tenant Perusahaan (Khusus Global Super Admin)"
              >
                <option value={0}>Semua Perusahaan (Global)</option>
                {(userContext.companies || []).map((c) => (
                  <option key={c.companyId} value={c.companyId}>
                    Tenant: {c.companyName} ({c.companyCode})
                  </option>
                ))}
              </select>
            )}

            <div className={styles.roleBadge} title="Hak Akses dari adm_mst_role_menu">
              <span>{userContext?.roleName || "User"}</span>
              <span>·</span>
              <span>{canApprovePromo ? "Checker (Approve)" : canEditPromo ? "Maker (Add/Edit)" : "Viewer"}</span>
            </div>

            <div className={styles.seg}>
              <button
                className={`${styles.segBtn} ${
                  currency === "IDR" ? styles.segBtnOn : ""
                }`}
                onClick={() => setCurrency("IDR")}
              >
                IDR
              </button>
              <button
                className={`${styles.segBtn} ${
                  currency === "USD" ? styles.segBtnOn : ""
                }`}
                onClick={() => setCurrency("USD")}
              >
                USD
              </button>
            </div>
            <div className={styles.seg}>
              <button
                className={`${styles.segBtn} ${
                  lang === "id" ? styles.segBtnOn : ""
                }`}
                onClick={() => setLang("id")}
              >
                ID
              </button>
              <button
                className={`${styles.segBtn} ${
                  lang === "en" ? styles.segBtnOn : ""
                }`}
                onClick={() => setLang("en")}
              >
                EN
              </button>
            </div>
          </div>
        </header>

        <main className={styles.content}>
          {currentMenuPerm.view !== 1 ? (
            <div className={styles.noAccessBox}>
              <div style={{ fontWeight: 700, fontSize: 15, marginBottom: 6 }}>
                Akses Modul Dibatasi (Multi-Tenant &amp; RBAC Protection)
              </div>
              <div>
                Perusahaan <strong>{userContext?.companyName}</strong> atau Role{" "}
                <strong>{userContext?.roleName}</strong> tidak berlangganan / tidak memiliki izin{" "}
                <code>VIEW</code> pada menu <code>{activeMenuCode}</code>.
              </div>
              <div style={{ marginTop: 8, fontSize: 12.5, color: "#7f1d1d" }}>
                Silakan hubungi Global Super Admin untuk mengaktifkan aplikasi{" "}
                <code>PROMO</code> di <code>adm_mst_company_application</code> /{" "}
                <code>adm_mst_company_module</code> atau hubungi Company Admin untuk mengatur{" "}
                <code>adm_mst_role_menu</code>.
              </div>
            </div>
          ) : (
            children
          )}
        </main>
      </div>

      {selectedPromo && renderDrawerDetails(selectedPromo)}

      {modalState.open && modalState.promo && (
        <div
          className={styles.modalBg}
          onClick={(e) => {
            if (e.target === e.currentTarget) closeModalAction();
          }}
        >
          <div className={styles.modal}>
            <div style={{ fontWeight: 600, fontSize: 15 }}>
              {tr(
                modalState.kind === "extend"
                  ? "ext"
                  : modalState.kind === "request"
                  ? "req"
                  : modalState.kind,
                lang
              )}{" "}
              — {modalState.promo.code}
            </div>

            {modalState.kind === "extend" && (
              <div className={styles.field}>
                <label>
                  {tr("newExp", lang)} ({tr("ex2", lang)})
                </label>
                <input
                  type="date"
                  value={newExpiresAt}
                  min={modalState.promo.expiresAt?.slice(0, 10)}
                  onChange={(e) => setNewExpiresAt(e.target.value)}
                />
              </div>
            )}

            <div className={styles.field}>
              <label>{tr("reason", lang)}</label>
              <textarea
                rows={3}
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="Tuliskan alasan perubahan / keputusan..."
              />
            </div>

            <div style={{ display: "flex", justifyContent: "flex-end", gap: 8 }}>
              <button
                className={styles.btn}
                onClick={closeModalAction}
                disabled={submitting}
              >
                {tr("cancel", lang)}
              </button>
              <button
                className={`${styles.btn} ${styles.btnPri}`}
                onClick={handleConfirmModal}
                disabled={submitting}
              >
                {submitting ? "..." : tr("ok", lang)}
              </button>
            </div>
          </div>
        </div>
      )}

      {toastMsg && <div className={styles.toast}>{toastMsg}</div>}
    </div>
  );
}
