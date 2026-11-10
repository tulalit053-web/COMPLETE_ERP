"use client";

import React, { useState, useMemo, useEffect } from "react";
import styles from "./Dashboard.module.css";
import "./Dashboard.module.css";
import {
  AdminSessionContext,
  PortalMenuItem,
  getWorkspaceRowsForMenu,
} from "./dashboard.service";
import { resolveDashboardConfig } from "./dashboard-profiles";

const c = (name: string) =>
  styles && (styles as Record<string, string>)[name]
    ? `${(styles as Record<string, string>)[name]} ${name}`
    : name;

interface DashboardViewProps {
  session: AdminSessionContext | null;
  loading: boolean;
  error: string;
  promoWebUrl: string;
  selectedCompanyId: number | null;
  onSwitchCompany: (companyId: number | null) => void;
  onLogout: () => void;
}

export default function DashboardView({
  session,
  loading,
  error,
  promoWebUrl,
  selectedCompanyId,
  onSwitchCompany,
  onLogout,
}: DashboardViewProps) {
  const [activeTab, setActiveTab] = useState<"dashboard" | "rbac" | "menu">("dashboard");
  const [selectedMenu, setSelectedMenu] = useState<PortalMenuItem | null>(null);
  const [selectedDashboardApp, setSelectedDashboardApp] = useState<string>("AUTO");
  const [searchQuery, setSearchQuery] = useState("");
  const [openApps, setOpenApps] = useState<Record<string, boolean>>({});
  const [openGroups, setOpenGroups] = useState<Record<string, boolean>>({});
  const [aiPrompt, setAiPrompt] = useState("");
  const [aiAnswer, setAiAnswer] = useState<string | null>(null);
  const [actionToast, setActionToast] = useState<string | null>(null);
  const [now, setNow] = useState<Date | null>(null);

  useEffect(() => {
    setNow(new Date());
    const t = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(t);
  }, []);

  // Reset app tab to AUTO when user or company changes
  useEffect(() => {
    if (!session) return;
    const roleLower = (session.roleName || "").toLowerCase();
    if (roleLower.includes("accounting") || session.username === "siti.acc") {
      setSelectedDashboardApp("ACC");
    } else if (roleLower.includes("crm") || session.username === "andi.crm") {
      setSelectedDashboardApp("CRM");
    } else if (roleLower.includes("hr") || session.username === "dewi.hr") {
      setSelectedDashboardApp("HRD");
    } else {
      setSelectedDashboardApp("AUTO");
    }
  }, [session?.username, session?.companyId, session?.roleName]);

  const dateText = now
    ? now.toLocaleDateString("id-ID", {
        weekday: "long",
        day: "2-digit",
        month: "long",
        year: "numeric",
      })
    : "";
  const timeText = now
    ? now.toLocaleTimeString("id-ID", { hour12: false }).replace(/\./g, ":") + " WIB"
    : "";

  const triggerToast = (msg: string) => {
    setActionToast(msg);
    setTimeout(() => {
      setActionToast((prev) => (prev === msg ? null : prev));
    }, 3200);
  };

  const toggleApp = (key: string) =>
    setOpenApps((prev) => ({ ...prev, [key]: !(prev[key] ?? true) }));

  const toggleGroup = (key: string) => {
    setOpenGroups((prev) => ({
      ...prev,
      [key]: prev[key] === undefined ? false : !prev[key],
    }));
  };

  const filteredApps = useMemo(() => {
    if (!session) return [];
    const q = searchQuery.trim().toLowerCase();
    if (!q) return session.subscribedApplications;
    return session.subscribedApplications
      .map((app) => ({
        ...app,
        modules: app.modules
          .map((mod) => ({
            ...mod,
            menus: mod.menus.filter(
              (m) =>
                m.menuName.toLowerCase().includes(q) ||
                m.menuCode.toLowerCase().includes(q) ||
                mod.moduleName.toLowerCase().includes(q)
            ),
          }))
          .filter((mod) => mod.menus.length > 0),
      }))
      .filter((app) => app.modules.length > 0);
  }, [session, searchQuery]);

  if (loading && !session) {
    return (
      <div className={c("shLayout")} style={{ alignItems: "center", justifyContent: "center" }}>
        <div className={c("shCard")} style={{ padding: "32px 48px", textAlign: "center" }}>
          <div style={{ fontSize: 16, fontWeight: 700, color: "#2563eb", marginBottom: 6 }}>
            Memuat ERP Enterprise Workspace...
          </div>
          <div style={{ fontSize: 13, color: "#64748b" }}>
            Menyinkronkan User, Role, Company Subscription, & Menu dari schema_admin
          </div>
        </div>
      </div>
    );
  }

  const subscribedCodes =
    session?.subscribedApplications.map((a) => a.applicationCode) || [];
  const dashConfig = resolveDashboardConfig(selectedDashboardApp, subscribedCodes);

  const totalMenus = session?.menus.length || 0;
  const addableMenus = session?.menus.filter((m) => m.canAdd).length || 0;
  const approvableMenus = session?.menus.filter((m) => m.canApprove).length || 0;
  const hasPromoSubscription = subscribedCodes.includes("PROMO");

  const initials = (session?.fullName || "U")
    .split(" ")
    .map((w) => w[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();

  const handleSelectMenu = (menu: PortalMenuItem) => {
    setSelectedMenu(menu);
    setActiveTab("menu");
  };

  const handleOpenMenuByCode = (menuCode?: string) => {
    if (!menuCode || !session) return;
    const found = session.menus.find((m) => m.menuCode === menuCode);
    if (found) {
      handleSelectMenu(found);
    } else {
      triggerToast(`Membuka rincian item (${menuCode})`);
    }
  };

  const handleAskAi = (e: React.FormEvent) => {
    e.preventDefault();
    if (!session) return;
    const q = aiPrompt.trim().toLowerCase();
    if (!q) return;

    if (q.includes("role") || q.includes("akses") || q.includes("permission")) {
      setAiAnswer(
        `Role Anda '${session.roleName}' memiliki akses ke ${totalMenus} menu (${addableMenus} Maker, ${approvableMenus} Checker).`
      );
    } else if (q.includes("promo")) {
      setAiAnswer(
        hasPromoSubscription
          ? `${session.companyName} berlangganan Promotion System. Klik menu PROMO di sidebar atau tombol biru di kiri bawah.`
          : `${session.companyName} tidak berlangganan modul Promotion System.`
      );
    } else {
      setAiAnswer(
        `Dashboard aktif: ${dashConfig.title} (${dashConfig.chartPrimaryValue}, ${dashConfig.chartBadge}).`
      );
    }
    setAiPrompt("");
  };

  const activeWorkspaceRows =
    selectedMenu && session
      ? getWorkspaceRowsForMenu(selectedMenu, session.companyName)
      : [];

  const activeTicks = Math.round((dashConfig.gaugePercent / 100) * 24);

  return (
    <div className={c("shLayout")}>
      {/* ================= LEFT SIDEBAR ================= */}
      <aside className={c("shSidebar")}>
        <div className={c("shBrandRow")}>
          <div className={c("shBrandLeft")}>
            <div className={c("shBrandIcon")}>S</div>
            <div>
              <div className={c("shBrandName")}>ERP Nexa</div>
              <div className={c("shBrandSub")}>Enterprise Portal</div>
            </div>
          </div>
          <button
            type="button"
            className={c("shCollapseBtn")}
            title="Multi-Tenant Navigation"
          >
            ◫
          </button>
        </div>

        <div className={c("shNavScroll")}>
          {/* Primary Navigation */}
          <button
            type="button"
            onClick={() => {
              setActiveTab("dashboard");
              setSelectedMenu(null);
            }}
            className={`${c("shNavItem")} ${
              activeTab === "dashboard" ? c("shNavItemActive") : ""
            }`}
          >
            <span className={c("shNavItemLeft")}>
              <span className={c("shNavIcon")}>🧭</span>
              <span>Dashboard</span>
            </span>
          </button>

          {/* Dynamic Subscribed Applications & Modules from schema_admin */}
          {filteredApps.map((app) => {
            const appKey = `app-${app.applicationId}`;
            const isAppOpen = openApps[appKey] ?? true;
            return (
              <React.Fragment key={app.applicationId}>
                <button
                  type="button"
                  onClick={() => toggleApp(appKey)}
                  className={c("shNavSectionLabel")}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    width: "100%",
                    background: "transparent",
                    border: "none",
                    cursor: "pointer",
                    textAlign: "left",
                  }}
                >
                  <span>
                    [{app.applicationCode}] {app.applicationName}
                  </span>
                  <span style={{ fontSize: 10 }}>{isAppOpen ? "▴" : "▾"}</span>
                </button>

                {isAppOpen &&
                  app.modules.map((mod) => {
                    const groupKey = `${app.applicationId}-${mod.moduleId}`;
                    const isOpen = openGroups[groupKey] ?? true;
                    const isModActive =
                      activeTab === "menu" &&
                      selectedMenu?.moduleId === mod.moduleId &&
                      selectedMenu?.applicationId === app.applicationId;

                    const modIcon =
                      app.applicationCode === "HRD"
                        ? "👥"
                        : app.applicationCode === "ACC"
                        ? "🏛️"
                        : app.applicationCode === "CRM"
                        ? "🤝"
                        : "🏷️";

                    return (
                      <div key={groupKey}>
                        <button
                          type="button"
                          onClick={() => toggleGroup(groupKey)}
                          className={`${c("shNavItem")} ${
                            isModActive ? c("shNavItemActive") : ""
                          }`}
                        >
                          <span className={c("shNavItemLeft")}>
                            <span className={c("shNavIcon")}>{modIcon}</span>
                            <span
                              style={{
                                overflow: "hidden",
                                textOverflow: "ellipsis",
                                whiteSpace: "nowrap",
                              }}
                            >
                              {mod.moduleName}
                            </span>
                          </span>
                          <span style={{ display: "flex", alignItems: "center", gap: 6 }}>
                            <span className={c("shNavBadgeBlue")}>
                              {mod.menus.length}
                            </span>
                            <span style={{ fontSize: 10, color: "#94a3b8" }}>
                              {isOpen ? "▴" : "▾"}
                            </span>
                          </span>
                        </button>

                        {isOpen && (
                          <div className={c("shSubMenuWrap")}>
                            {mod.menus.map((menu) => {
                              const isSelected =
                                activeTab === "menu" &&
                                selectedMenu?.menuId === menu.menuId;
                              return (
                                <button
                                  key={menu.menuId}
                                  type="button"
                                  onClick={() => handleSelectMenu(menu)}
                                  className={`${c("shSubMenuItem")} ${
                                    isSelected ? c("shSubMenuItemActive") : ""
                                  }`}
                                >
                                  <span
                                    style={{
                                      overflow: "hidden",
                                      textOverflow: "ellipsis",
                                      whiteSpace: "nowrap",
                                    }}
                                  >
                                    {menu.menuName}
                                  </span>
                                  {menu.canApprove && (
                                    <span
                                      title="Punya Hak Approve (Checker)"
                                      style={{
                                        fontSize: 10,
                                        color: "#059669",
                                        fontWeight: 700,
                                      }}
                                    >
                                      ✓
                                    </span>
                                  )}
                                </button>
                              );
                            })}
                          </div>
                        )}
                      </div>
                    );
                  })}
              </React.Fragment>
            );
          })}
        </div>

        {/* Slim Bottom Footer Card (Tanpa Duplikasi Nama PT / Role) */}
        <div className={c("shSidebarFooter")}>
          <div className={c("shPremiumCard")}>
            <div className={c("shPremiumTitle")}>
              {hasPromoSubscription ? "PromoHub Engine" : "Matriks Hak Akses"}
            </div>
            <div className={c("shPremiumDesc")}>
              {subscribedCodes.length} Aplikasi • {totalMenus} Menu Aktif
            </div>
            {hasPromoSubscription ? (
              <a
                href={`${promoWebUrl}/dashboard/overview?username=${encodeURIComponent(
                  session?.username || "budi.santoso"
                )}`}
                className={c("shPremiumBtn")}
              >
                Buka PromoHub (:3001) ↗
              </a>
            ) : (
              <button
                type="button"
                onClick={() => setActiveTab("rbac")}
                className={c("shPremiumBtn")}
              >
                Lihat Matriks RBAC
              </button>
            )}
          </div>
        </div>
      </aside>

      {/* ================= MAIN WORKSPACE ================= */}
      <div className={c("shMain")}>
        {/* Topbar */}
        <header className={c("shTopbar")}>
          <div className={c("shSearchBox")}>
            <span style={{ color: "#94a3b8", fontSize: 14 }}>🔍</span>
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Search menu, module, or code..."
              className={c("shSearchInput")}
            />
            <span className={c("shSearchShortcut")}>⌘K</span>
          </div>

          <div className={c("shTopbarRight")}>
            {/* Perusahaan aktif + tanggal & jam (Satu-satunya tempat Nama Perusahaan tampil) */}
            <div
              style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "flex-end",
                lineHeight: 1.25,
                paddingRight: 6,
              }}
            >
              <span style={{ fontSize: 13, fontWeight: 800, color: "#0f172a" }}>
                🏢{" "}
                {session?.globalSuperAdmin && !selectedCompanyId
                  ? "Global Holding (Semua PT)"
                  : session?.companyName}
              </span>
              <span
                style={{ fontSize: 11, color: "#64748b" }}
                suppressHydrationWarning
              >
                {dateText} • {timeText}
              </span>
            </div>

            <button
              type="button"
              onClick={() => setActiveTab("rbac")}
              className={c("shIconBtn")}
              title="Lihat Matriks Hak Akses Role & Menu"
            >
              🛡️
            </button>

            {/* User Pill: Hanya Nama & Role (Tidak mengulang Nama PT) */}
            <div className={c("shUserPill")}>
              <div className={c("shAvatar")}>{initials}</div>
              <div className={c("shUserMeta")}>
                <span className={c("shUserName")}>{session?.fullName}</span>
                <span className={c("shUserRole")}>{session?.roleName}</span>
              </div>
            </div>

            <button
              type="button"
              onClick={onLogout}
              className={c("shPillBtn")}
              style={{
                color: "#e11d48",
                borderColor: "#fecdd3",
                background: "#fff1f2",
              }}
            >
              Keluar
            </button>
          </div>
        </header>

        {/* Main Content Canvas */}
        <main className={c("shCanvas")}>
          {error && (
            <div
              className={c("shCard")}
              style={{
                borderColor: "#fecdd3",
                background: "#fff1f2",
                color: "#be123c",
                marginBottom: 16,
              }}
            >
              {error}
            </div>
          )}

          {actionToast && (
            <div
              style={{
                background: "#0f172a",
                color: "#ffffff",
                padding: "10px 18px",
                borderRadius: 999,
                fontSize: 13,
                fontWeight: 600,
                marginBottom: 16,
                display: "inline-flex",
                alignItems: "center",
                gap: 8,
                boxShadow: "0 8px 20px rgba(15, 23, 42, 0.2)",
              }}
            >
              <span>✨</span>
              <span>{actionToast}</span>
            </div>
          )}

          {/* ================= TAB 1: ROLE & APPLICATION-SPECIFIC DASHBOARD ================= */}
          {activeTab === "dashboard" && (
            <>
              <div className={c("shPageHeader")}>
                <div>
                  <h1 className={c("shPageTitle")}>{dashConfig.title}</h1>
                  <div className={c("shPageSubtitle")}>{dashConfig.subtitle}</div>

                  {/* Jika user memiliki akses ke > 1 aplikasi (mis. budi.santoso / andi.crm / test_admin),
                      sediakan pill tab untuk berpindah tampilan dashboard antar aplikasi */}
                  {subscribedCodes.length > 1 && (
                    <div
                      style={{
                        display: "flex",
                        flexWrap: "wrap",
                        gap: 8,
                        marginTop: 12,
                      }}
                    >
                      <button
                        type="button"
                        onClick={() => setSelectedDashboardApp("AUTO")}
                        className={c("shPillBtn")}
                        style={
                          selectedDashboardApp === "AUTO"
                            ? {
                                background: "#2563eb",
                                color: "#ffffff",
                                borderColor: "#2563eb",
                              }
                            : undefined
                        }
                      >
                        📊 Ringkasan Terpadu
                      </button>
                      {session?.subscribedApplications.map((app) => (
                        <button
                          key={app.applicationId}
                          type="button"
                          onClick={() =>
                            setSelectedDashboardApp(app.applicationCode)
                          }
                          className={c("shPillBtn")}
                          style={
                            selectedDashboardApp === app.applicationCode
                              ? {
                                  background: "#2563eb",
                                  color: "#ffffff",
                                  borderColor: "#2563eb",
                                }
                              : undefined
                          }
                        >
                          {app.applicationCode === "HRD"
                            ? "👥 "
                            : app.applicationCode === "ACC"
                            ? "🏛️ "
                            : app.applicationCode === "CRM"
                            ? "🤝 "
                            : "🏷️ "}
                          {app.applicationName}
                        </button>
                      ))}
                    </div>
                  )}
                </div>

                <div className={c("shHeaderActions")}>
                  {/* Dropdown Filter Perusahaan (Di Kanan Atas Bawah Header - Khusus Super Admin Global) */}
                  {session?.globalSuperAdmin && (
                    <select
                      value={selectedCompanyId ?? ""}
                      onChange={(e) => {
                        const val = e.target.value ? Number(e.target.value) : null;
                        onSwitchCompany(val);
                      }}
                      className={c("shSelectPill")}
                      title="Filter Perusahaan (Super Admin Global)"
                    >
                      <option value="">🌐 Semua Perusahaan</option>
                      {session.companies.map((comp) => (
                        <option key={comp.companyId} value={comp.companyId}>
                          🏢 {comp.companyName}
                        </option>
                      ))}
                    </select>
                  )}

                  <span className={c("shPillBtn")}>Last 30 days ▾</span>

                  <button
                    type="button"
                    onClick={() =>
                      triggerToast(
                        `Laporan ${dashConfig.title} berhasil diekspor.`
                      )
                    }
                    className={c("shPrimaryBtn")}
                  >
                    ⬇ Export
                  </button>
                </div>
              </div>

              {/* Row 1: 4 Domain-Specific KPI Cards */}
              <div className={c("shKpiGrid")}>
                {dashConfig.kpis.map((kpi) => (
                  <div key={kpi.label} className={c("shCard")}>
                    <div className={c("shKpiTop")}>
                      <span className={c("shKpiLabel")}>{kpi.label}</span>
                      <span className={c("shKpiIcon")}>{kpi.icon}</span>
                    </div>
                    <div className={c("shKpiValueRow")}>
                      <span className={c("shKpiValue")}>{kpi.value}</span>
                      <span
                        className={
                          kpi.badgeUp ? c("shBadgeUp") : c("shBadgeDown")
                        }
                      >
                        {kpi.badge}
                      </span>
                    </div>
                    <div className={c("shKpiComp")}>{kpi.subtitle}</div>
                  </div>
                ))}
              </div>

              {/* Row 2: Domain Trend Chart + 3-Segment Breakdown (Left 2/3) & Weekly Bars + Radial Gauge (Right 1/3) */}
              <div className={c("shMainGrid")}>
                {/* Left 2/3 Card */}
                <div className={c("shCard")}>
                  <div className={c("shCardHeader")}>
                    <span className={c("shCardTitle")}>{dashConfig.chartTitle}</span>
                    <span style={{ color: "#94a3b8", fontSize: 14 }}>•••</span>
                  </div>

                  <div className={c("shProfitRow")}>
                    <div>
                      <div className={c("shBigProfit")}>
                        {dashConfig.chartPrimaryValue}
                      </div>
                      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                        <span className={c("shBadgeUp")}>
                          {dashConfig.chartBadge}
                        </span>
                        <span className={c("shKpiComp")}>vs. last period</span>
                      </div>
                    </div>

                    {/* Interactive Dual-Line Area SVG Chart */}
                    <div style={{ position: "relative", width: "100%", height: 155 }}>
                      <svg
                        viewBox="0 0 520 140"
                        style={{
                          width: "100%",
                          height: "100%",
                          overflow: "visible",
                        }}
                      >
                        <defs>
                          <linearGradient id="shBlueGrad" x1="0" y1="0" x2="0" y2="1">
                            <stop offset="0%" stopColor="#2563eb" stopOpacity="0.22" />
                            <stop offset="100%" stopColor="#2563eb" stopOpacity="0.0" />
                          </linearGradient>
                        </defs>
                        <line x1="30" y1="25" x2="505" y2="25" stroke="#f1f5f9" strokeWidth="1" />
                        <line x1="30" y1="65" x2="505" y2="65" stroke="#f1f5f9" strokeWidth="1" />
                        <line x1="30" y1="105" x2="505" y2="105" stroke="#f1f5f9" strokeWidth="1" />
                        <text x="0" y="29" fill="#94a3b8" fontSize="10">High</text>
                        <text x="0" y="69" fill="#94a3b8" fontSize="10">Mid</text>
                        <text x="0" y="109" fill="#94a3b8" fontSize="10">Base</text>

                        <path d={dashConfig.svgPathArea} fill="url(#shBlueGrad)" />
                        <path
                          d={dashConfig.svgPathSecondary}
                          fill="none"
                          stroke="#94a3b8"
                          strokeWidth="1.8"
                          strokeDasharray="4 4"
                        />
                        <path
                          d={dashConfig.svgPathPrimary}
                          fill="none"
                          stroke="#2563eb"
                          strokeWidth="2.6"
                        />
                        <line
                          x1="235"
                          y1="15"
                          x2="235"
                          y2="115"
                          stroke="#cbd5e1"
                          strokeWidth="1.2"
                          strokeDasharray="3 3"
                        />
                        <circle
                          cx="235"
                          cy="52"
                          r="4.5"
                          fill="#2563eb"
                          stroke="#ffffff"
                          strokeWidth="2"
                        />
                        <text x="35" y="132" fill="#94a3b8" fontSize="10">1 Nov</text>
                        <text x="145" y="132" fill="#94a3b8" fontSize="10">8 Nov</text>
                        <text x="260" y="132" fill="#94a3b8" fontSize="10">15 Nov</text>
                        <text x="375" y="132" fill="#94a3b8" fontSize="10">22 Nov</text>
                        <text x="468" y="132" fill="#94a3b8" fontSize="10">29 Nov</text>
                      </svg>

                      <div
                        style={{
                          position: "absolute",
                          top: 12,
                          left: "47%",
                          background: "#ffffff",
                          border: "1px solid #e2e8f0",
                          borderRadius: 10,
                          padding: "8px 12px",
                          boxShadow: "0 8px 20px rgba(15, 23, 42, 0.08)",
                          fontSize: 11,
                          pointerEvents: "none",
                        }}
                      >
                        <div style={{ color: "#64748b", marginBottom: 3 }}>
                          {dashConfig.chartTooltipTitle}
                        </div>
                        <div style={{ fontWeight: 700, color: "#0f172a" }}>
                          <span style={{ color: "#2563eb" }}>●</span>{" "}
                          {dashConfig.chartTooltipPrimary}
                        </div>
                        <div style={{ color: "#64748b" }}>
                          <span>⋯</span> {dashConfig.chartTooltipSecondary}
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* 3-Column Segment Breakdown Box */}
                  <div className={c("shCustomerBox")}>
                    <div className={c("shCardHeader")} style={{ marginBottom: 4 }}>
                      <span
                        style={{
                          fontSize: 13.5,
                          fontWeight: 700,
                          color: "#0f172a",
                        }}
                      >
                        {dashConfig.segmentBoxTitle}
                      </span>
                      <span style={{ color: "#94a3b8", fontSize: 14 }}>•••</span>
                    </div>

                    <div className={c("shSegmentGrid")}>
                      {dashConfig.segments.map((seg) => (
                        <div key={seg.label} className={c("shSegmentItem")}>
                          <div className={c("shSegmentVal")}>
                            <span>{seg.icon}</span> {seg.value}
                          </div>
                          <div className={c("shSegmentLbl")}>{seg.label}</div>
                          <div className={c("shBarTrack")}>
                            <div
                              style={{
                                width: `${seg.percent}%`,
                                height: "100%",
                                background: seg.color,
                              }}
                            />
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>

                {/* Right 1/3 Column */}
                <div className={c("shRightStack")}>
                  <div className={c("shCard")}>
                    <div className={c("shCardHeader")}>
                      <span className={c("shCardTitle")}>
                        {dashConfig.weekTitle}
                      </span>
                      <span style={{ color: "#94a3b8" }}>•••</span>
                    </div>

                    <div className={c("shWeekChart")}>
                      {dashConfig.weekBars.map((bar) => (
                        <div key={bar.day} className={c("shDayCol")}>
                          <div
                            className={`${c("shDayBar")} ${
                              bar.active ? c("shDayBarActive") : ""
                            }`}
                            style={{ height: bar.height }}
                          >
                            {bar.val && (
                              <span className={c("shDayBarTopVal")}>{bar.val}</span>
                            )}
                          </div>
                          <span
                            className={`${c("shDayLbl")} ${
                              bar.active ? c("shDayLblActive") : ""
                            }`}
                          >
                            {bar.day}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>

                  {/* Semi-Circle Radial Gauge Card */}
                  <div className={c("shCard")} style={{ textAlign: "center" }}>
                    <div className={c("shCardHeader")}>
                      <span className={c("shCardTitle")}>
                        {dashConfig.gaugeTitle}
                      </span>
                      <span style={{ color: "#94a3b8" }}>•••</span>
                    </div>

                    <div style={{ position: "relative", height: 120, marginTop: 4 }}>
                      <svg
                        viewBox="0 0 220 120"
                        style={{ width: 210, height: 115, margin: "0 auto" }}
                      >
                        {Array.from({ length: 24 }).map((_, idx) => {
                          const angle = -180 + (idx / 23) * 180;
                          const rad = (angle * Math.PI) / 180;
                          const cx = 110;
                          const cy = 102;
                          const x1 = cx + 72 * Math.cos(rad);
                          const y1 = cy + 72 * Math.sin(rad);
                          const x2 = cx + 88 * Math.cos(rad);
                          const y2 = cy + 88 * Math.sin(rad);
                          const isFilled = idx < activeTicks;
                          return (
                            <line
                              key={idx}
                              x1={x1}
                              y1={y1}
                              x2={x2}
                              y2={y2}
                              stroke={isFilled ? "#10b981" : "#e2e8f0"}
                              strokeWidth="4.5"
                              strokeLinecap="round"
                            />
                          );
                        })}
                      </svg>
                      <div
                        style={{
                          position: "absolute",
                          bottom: 6,
                          left: 0,
                          right: 0,
                          textAlign: "center",
                        }}
                      >
                        <div
                          style={{
                            fontSize: 30,
                            fontWeight: 800,
                            color: "#0f172a",
                            lineHeight: 1,
                          }}
                        >
                          {dashConfig.gaugePercent}%
                        </div>
                        <div
                          style={{
                            fontSize: 11.5,
                            color: "#64748b",
                            marginTop: 4,
                          }}
                        >
                          {dashConfig.gaugeSubtitle}
                        </div>
                      </div>
                    </div>

                    <button
                      type="button"
                      onClick={() => setActiveTab("rbac")}
                      className={c("shPillBtn")}
                      style={{ marginTop: 8, fontSize: 12 }}
                    >
                      Show details
                    </button>
                  </div>
                </div>
              </div>

              {/* Row 3: Domain Operational Table (Left 2/3) & AI Assistant (Right 1/3) */}
              <div className={c("shMainGrid")} style={{ marginBottom: 0 }}>
                <div className={c("shCard")}>
                  <div className={c("shCardHeader")}>
                    <span className={c("shCardTitle")}>{dashConfig.tableTitle}</span>
                    <span style={{ color: "#94a3b8" }}>•••</span>
                  </div>

                  <div className={c("shTableWrap")}>
                    <table className={c("shTable")}>
                      <thead>
                        <tr>
                          {dashConfig.tableHeaders.map((h) => (
                            <th key={h}>{h}</th>
                          ))}
                        </tr>
                      </thead>
                      <tbody>
                        {dashConfig.tableRows.map((row) => (
                          <tr
                            key={row.id}
                            onClick={() => handleOpenMenuByCode(row.menuCode)}
                            style={{ cursor: "pointer" }}
                          >
                            <td style={{ fontWeight: 700, color: "#64748b" }}>
                              {row.id}
                            </td>
                            <td>
                              <div style={{ fontWeight: 700, color: "#0f172a" }}>
                                {row.name}
                              </div>
                              <div style={{ fontSize: 11.5, color: "#94a3b8" }}>
                                {row.sub}
                              </div>
                            </td>
                            <td>
                              <span className={c("shNavBadgeBlue")}>
                                {row.category}
                              </span>
                            </td>
                            <td>
                              <span className={c("shBadgeUp")}>{row.metric}</span>
                            </td>
                            <td style={{ fontWeight: 600 }}>⭐ ({row.rating})</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>

                {/* Right 1/3: AI Assistant Card */}
                <div className={c("shCard")}>
                  <div className={c("shCardHeader")}>
                    <span className={c("shCardTitle")}>AI Assistant</span>
                    <span style={{ color: "#94a3b8", fontSize: 13 }}>↗</span>
                  </div>

                  <div className={c("shAiBox")}>
                    <div className={c("shAiOrb")} />

                    <div className={c("shAiReply")}>
                      {aiAnswer ||
                        `Asisten pintar untuk ${dashConfig.title}. Tanyakan ringkasan metrik atau hak akses modul.`}
                    </div>

                    <form onSubmit={handleAskAi} className={c("shAiInputRow")}>
                      <span style={{ color: "#94a3b8", fontSize: 13 }}>📎</span>
                      <input
                        type="text"
                        value={aiPrompt}
                        onChange={(e) => setAiPrompt(e.target.value)}
                        placeholder="Ask me anything..."
                        className={c("shAiInput")}
                      />
                      <button type="submit" className={c("shAiSendBtn")}>
                        ↑
                      </button>
                    </form>
                  </div>
                </div>
              </div>
            </>
          )}

          {/* ================= TAB 2: ACTIVE MENU WORKSPACE ================= */}
          {activeTab === "menu" && selectedMenu && (
            <>
              <div className={c("shPageHeader")}>
                <div>
                  <div
                    style={{
                      fontSize: 12,
                      fontWeight: 700,
                      color: "#2563eb",
                      marginBottom: 4,
                    }}
                  >
                    [{selectedMenu.applicationCode}] {selectedMenu.applicationName} /{" "}
                    {selectedMenu.moduleName} / {selectedMenu.menuCode}
                  </div>
                  <h1 className={c("shPageTitle")}>{selectedMenu.menuName}</h1>
                  <div className={c("shPageSubtitle")}>
                    Route: <code>{selectedMenu.menuLink}</code> • Sumber Hak Akses:{" "}
                    <strong>{selectedMenu.permissionSource}</strong>
                  </div>
                </div>

                <div className={c("shHeaderActions")}>
                  <button
                    type="button"
                    onClick={() => setActiveTab("dashboard")}
                    className={c("shPillBtn")}
                  >
                    ← Kembali ke Dashboard
                  </button>

                  {selectedMenu.applicationCode === "PROMO" && (
                    <a
                      href={`${promoWebUrl}${selectedMenu.menuLink}?username=${encodeURIComponent(
                        session?.username || "budi.santoso"
                      )}`}
                      className={c("shPillBtn")}
                      style={{
                        borderColor: "#2563eb",
                        color: "#2563eb",
                        background: "#eff6ff",
                      }}
                    >
                      Buka Full Engine di PromoHub (:3001) ↗
                    </a>
                  )}

                  <button
                    type="button"
                    disabled={!selectedMenu.canAdd}
                    onClick={() =>
                      triggerToast(
                        `Form Tambah Data pada menu '${selectedMenu.menuName}' dibuka (is_add = 1).`
                      )
                    }
                    className={c("shPrimaryBtn")}
                  >
                    {selectedMenu.canAdd
                      ? `+ Tambah ${selectedMenu.menuName}`
                      : "🔒 Tambah Dikunci (is_add = 0)"}
                  </button>
                </div>
              </div>

              {/* Schema Admin Permission Bar for this Menu */}
              <div className={c("shCard")} style={{ marginBottom: 18 }}>
                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    flexWrap: "wrap",
                    gap: 12,
                  }}
                >
                  <div style={{ fontSize: 13, fontWeight: 700, color: "#0f172a" }}>
                    Hak Akses Menu ({selectedMenu.menuCode})
                  </div>
                  <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                    <span
                      className={`${c("shPermTag")} ${
                        selectedMenu.canView ? c("shPermOn") : c("shPermOff")
                      }`}
                    >
                      VIEW: {selectedMenu.canView ? "1" : "0"}
                    </span>
                    <span
                      className={`${c("shPermTag")} ${
                        selectedMenu.canAdd ? c("shPermOn") : c("shPermOff")
                      }`}
                    >
                      ADD: {selectedMenu.canAdd ? "1" : "0"}
                    </span>
                    <span
                      className={`${c("shPermTag")} ${
                        selectedMenu.canEdit ? c("shPermOn") : c("shPermOff")
                      }`}
                    >
                      EDIT: {selectedMenu.canEdit ? "1" : "0"}
                    </span>
                    <span
                      className={`${c("shPermTag")} ${
                        selectedMenu.canDelete ? c("shPermOn") : c("shPermOff")
                      }`}
                    >
                      DELETE: {selectedMenu.canDelete ? "1" : "0"}
                    </span>
                    <span
                      className={`${c("shPermTag")} ${
                        selectedMenu.canApprove ? c("shPermOn") : c("shPermOff")
                      }`}
                    >
                      APPROVE: {selectedMenu.canApprove ? "1" : "0"}
                    </span>
                  </div>
                </div>
              </div>

              {/* Operational Records Table for Selected Menu */}
              <div className={c("shCard")}>
                <div className={c("shCardHeader")}>
                  <span className={c("shCardTitle")}>
                    Data Operasional • {selectedMenu.menuName}
                  </span>
                  <span className={c("shNavBadgeGreen")}>
                    {activeWorkspaceRows.length} Records
                  </span>
                </div>

                <div className={c("shTableWrap")}>
                  <table className={c("shTable")}>
                    <thead>
                      <tr>
                        <th>ID</th>
                        <th>NAME / DESCRIPTION</th>
                        <th>MODULE / INFO</th>
                        <th>VALUE / METRIC</th>
                        <th>RATING</th>
                        <th>ACTIONS</th>
                      </tr>
                    </thead>
                    <tbody>
                      {activeWorkspaceRows.map((row) => (
                        <tr key={row.id}>
                          <td style={{ fontWeight: 700, color: "#64748b" }}>{row.id}</td>
                          <td>
                            <div style={{ fontWeight: 700, color: "#0f172a" }}>
                              {row.title}
                            </div>
                            <div style={{ fontSize: 11.5, color: "#94a3b8" }}>
                              {row.category}
                            </div>
                          </td>
                          <td style={{ color: "#475569" }}>{row.metricLabel}</td>
                          <td>
                            <span className={c("shBadgeUp")}>{row.metricValue}</span>
                          </td>
                          <td style={{ fontWeight: 600 }}>⭐ ({row.rating})</td>
                          <td>
                            <div style={{ display: "flex", gap: 6 }}>
                              <button
                                type="button"
                                disabled={!selectedMenu.canEdit}
                                onClick={() =>
                                  triggerToast(
                                    `Edit ${row.id} berhasil dijalankan (is_edit = 1).`
                                  )
                                }
                                className={c("shPillBtn")}
                                style={{
                                  padding: "4px 10px",
                                  fontSize: 11.5,
                                  opacity: selectedMenu.canEdit ? 1 : 0.45,
                                }}
                              >
                                ✏️ Edit
                              </button>
                              <button
                                type="button"
                                disabled={!selectedMenu.canApprove}
                                onClick={() =>
                                  triggerToast(
                                    `Approve ${row.id} disahkan (is_approve = 1).`
                                  )
                                }
                                className={c("shPillBtn")}
                                style={{
                                  padding: "4px 10px",
                                  fontSize: 11.5,
                                  color: selectedMenu.canApprove
                                    ? "#059669"
                                    : "#94a3b8",
                                  borderColor: selectedMenu.canApprove
                                    ? "#a7f3d0"
                                    : "#e2e8f0",
                                  opacity: selectedMenu.canApprove ? 1 : 0.45,
                                }}
                              >
                                ✓ Approve
                              </button>
                            </div>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            </>
          )}

          {/* ================= TAB 3: SCHEMA ADMIN MATRIX INSPECTOR ================= */}
          {activeTab === "rbac" && (
            <>
              <div className={c("shPageHeader")}>
                <div>
                  <h1 className={c("shPageTitle")}>Matriks Hak Akses Menu</h1>
                  <div className={c("shPageSubtitle")}>
                    Daftar izin menu efektif dari <code>schema_admin</code>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => setActiveTab("dashboard")}
                  className={c("shPillBtn")}
                >
                  ← Kembali ke Dashboard
                </button>
              </div>

              <div className={c("shCard")}>
                <div className={c("shTableWrap")}>
                  <table className={c("shTable")}>
                    <thead>
                      <tr>
                        <th>MENU ID</th>
                        <th>CODE</th>
                        <th>MENU NAME</th>
                        <th>APP / MODULE</th>
                        <th>SOURCE</th>
                        <th>VIEW</th>
                        <th>ADD</th>
                        <th>EDIT</th>
                        <th>DELETE</th>
                        <th>APPROVE</th>
                      </tr>
                    </thead>
                    <tbody>
                      {session?.menus.map((m) => (
                        <tr key={m.menuId}>
                          <td>{m.menuId}</td>
                          <td style={{ fontWeight: 700 }}>{m.menuCode}</td>
                          <td style={{ fontWeight: 600 }}>{m.menuName}</td>
                          <td>
                            [{m.applicationCode}] {m.moduleName}
                          </td>
                          <td>
                            <span className={c("shNavBadgeBlue")}>
                              {m.permissionSource}
                            </span>
                          </td>
                          <td>{m.canView ? "✅ 1" : "❌ 0"}</td>
                          <td>{m.canAdd ? "✅ 1" : "❌ 0"}</td>
                          <td>{m.canEdit ? "✅ 1" : "❌ 0"}</td>
                          <td>{m.canDelete ? "✅ 1" : "❌ 0"}</td>
                          <td>{m.canApprove ? "✅ 1" : "❌ 0"}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            </>
          )}
        </main>
      </div>
    </div>
  );
}
