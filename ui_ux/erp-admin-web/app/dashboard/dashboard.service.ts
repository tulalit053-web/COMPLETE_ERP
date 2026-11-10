export interface RawPortalMenu {
  menuId: number;
  parentMenuId?: number | null;
  parentMenuCode?: string | null;
  parentMenuName?: string;
  menuCode: string;
  menuName: string;
  menuLink: string;
  moduleId: number;
  moduleName: string;
  applicationId: number;
  applicationCode: string;
  applicationName: string;
  permissionSource?: string;
  permissions?: {
    view: number;
    add: number;
    edit: number;
    delete: number;
    approve: number;
  };
}

export interface PortalMenuItem {
  menuId: number;
  parentMenuName: string;
  menuCode: string;
  menuName: string;
  menuLink: string;
  moduleId: number;
  moduleName: string;
  applicationId: number;
  applicationCode: string;
  applicationName: string;
  permissionSource: string;
  canView: boolean;
  canAdd: boolean;
  canEdit: boolean;
  canDelete: boolean;
  canApprove: boolean;
}

export interface AdminSessionContext {
  userId: number;
  username: string;
  fullName: string;
  email: string;
  employeeCode: string;
  companyId: number | null;
  companyCode: string | null;
  companyName: string;
  roleId: number | null;
  roleName: string;
  userRoles: Array<{ roleId: number; roleName: string; source: string }>;
  globalSuperAdmin: boolean;
  companies: Array<{ companyId: number; companyCode: string; companyName: string }>;
  availableUsers: Array<{
    username: string;
    name: string;
    companyId: number | null;
    companyName: string;
    roleName: string;
  }>;
  menus: PortalMenuItem[];
  subscribedApplications: Array<{
    applicationId: number;
    applicationCode: string;
    applicationName: string;
    modules: Array<{
      moduleId: number;
      moduleName: string;
      menus: PortalMenuItem[];
    }>;
  }>;
}

export interface MenuWorkspaceRow {
  id: string;
  title: string;
  category: string;
  metricLabel: string;
  metricValue: string;
  status: string;
  rating: string;
}

export async function fetchPortalContext(
  username?: string,
  companyId?: number | null
): Promise<AdminSessionContext> {
  const qs = new URLSearchParams();
  if (username) qs.set("username", username);
  if (companyId && companyId > 0) qs.set("companyId", String(companyId));

  const res = await fetch(`/api/portal/context?${qs.toString()}`, {
    method: "GET",
    headers: { "Content-Type": "application/json" },
    cache: "no-store",
  });

  if (!res.ok) {
    throw new Error(`Gagal memuat konteks portal (${res.status})`);
  }

  const raw = await res.json();
  const rawMenus: RawPortalMenu[] = Array.isArray(raw.menus) ? raw.menus : [];

  const flatMenus: PortalMenuItem[] = [];
  const appMap = new Map<
    number,
    {
      applicationId: number;
      applicationCode: string;
      applicationName: string;
      moduleMap: Map<
        number,
        {
          moduleId: number;
          moduleName: string;
          menus: PortalMenuItem[];
        }
      >;
    }
  >();

  for (const m of rawMenus) {
    const item: PortalMenuItem = {
      menuId: m.menuId,
      parentMenuName: m.parentMenuName || m.moduleName || "General",
      menuCode: m.menuCode,
      menuName: m.menuName,
      menuLink: m.menuLink,
      moduleId: m.moduleId || 999,
      moduleName: m.moduleName || "General",
      applicationId: m.applicationId || 99,
      applicationCode: m.applicationCode || "APP",
      applicationName: m.applicationName || "Application",
      permissionSource: m.permissionSource || "ROLE_MENU",
      canView: (m.permissions?.view ?? 1) === 1,
      canAdd: (m.permissions?.add ?? 0) === 1,
      canEdit: (m.permissions?.edit ?? 0) === 1,
      canDelete: (m.permissions?.delete ?? 0) === 1,
      canApprove: (m.permissions?.approve ?? 0) === 1,
    };
    flatMenus.push(item);

    const appId = item.applicationId;
    if (!appMap.has(appId)) {
      appMap.set(appId, {
        applicationId: appId,
        applicationCode: item.applicationCode,
        applicationName: item.applicationName,
        moduleMap: new Map(),
      });
    }
    const appGroup = appMap.get(appId)!;
    const modId = item.moduleId;
    if (!appGroup.moduleMap.has(modId)) {
      appGroup.moduleMap.set(modId, {
        moduleId: modId,
        moduleName: item.moduleName,
        menus: [],
      });
    }
    appGroup.moduleMap.get(modId)!.menus.push(item);
  }

  const subscribedApplications = Array.from(appMap.values()).map((a) => ({
    applicationId: a.applicationId,
    applicationCode: a.applicationCode,
    applicationName: a.applicationName,
    modules: Array.from(a.moduleMap.values()),
  }));

  return {
    userId: raw.userId ?? 8,
    username: raw.username || username || "budi.santoso",
    fullName: raw.fullName || raw.username || "Budi Santoso",
    email: raw.email || `${raw.username || "budi.santoso"}@erp.co.id`,
    employeeCode: raw.employeeCode || "EMP-001",
    companyId: raw.effectiveCompanyId ?? raw.userCompanyId ?? null,
    companyCode: raw.companyCode || "COMP01",
    companyName: raw.companyName || "PT Maju Jaya",
    roleId: raw.roleId ?? 1,
    roleName: raw.roleName || "Super Admin",
    userRoles: Array.isArray(raw.userRoles) ? raw.userRoles : [],
    globalSuperAdmin: Boolean(raw.isSuperAdmin),
    companies: Array.isArray(raw.companies) ? raw.companies : [],
    availableUsers: Array.isArray(raw.availableUsers) ? raw.availableUsers : [],
    menus: flatMenus,
    subscribedApplications,
  };
}

export function getWorkspaceRowsForMenu(
  menu: PortalMenuItem,
  companyName: string
): MenuWorkspaceRow[] {
  const code = menu.menuCode.toUpperCase();

  if (code.startsWith("HRD-EMP")) {
    return [
      { id: "#EMP-301", title: "Dewi Lestari (HR Manager)", category: "Human Capital • Permanent", metricLabel: "Masa Kerja: 4.2 Thn", metricValue: "Rp 18.500.000", status: "ACTIVE", rating: "4.9" },
      { id: "#EMP-302", title: "Rizky Pratama (Sr. Software Engineer)", category: "Engineering • Permanent", metricLabel: "Masa Kerja: 3.1 Thn", metricValue: "Rp 24.000.000", status: "ACTIVE", rating: "5.0" },
      { id: "#EMP-303", title: "Nadia Putri (UI/UX Specialist)", category: "Product Design • Contract", metricLabel: "Masa Kerja: 1.5 Thn", metricValue: "Rp 14.200.000", status: "ACTIVE", rating: "4.8" },
      { id: "#EMP-304", title: "Bagus Setiawan (DevOps Architect)", category: "Infrastructure • Permanent", metricLabel: "Masa Kerja: 2.8 Thn", metricValue: "Rp 26.500.000", status: "ACTIVE", rating: "4.9" },
      { id: "#EMP-305", title: "Alya Rahmawati (QA Analyst)", category: "Quality Assurance • Probation", metricLabel: "Masa Kerja: 0.4 Thn", metricValue: "Rp 10.800.000", status: "PROBATION", rating: "4.7" },
    ];
  }

  if (code.startsWith("HRD-ATT")) {
    return [
      { id: "#ATT-1101", title: "Shift Pagi - Head Office", category: "Check-in 08:02 WIB", metricLabel: "Kehadiran: 98.4%", metricValue: "142 / 145 Hadir", status: "ON_TIME", rating: "5.0" },
      { id: "#ATT-1102", title: "Remote Engineering Squad", category: "WFA Geo-Tag Verified", metricLabel: "Kehadiran: 100%", metricValue: "38 / 38 Hadir", status: "VERIFIED", rating: "4.9" },
      { id: "#ATT-1103", title: "Overtime Sprint Release", category: "Lembur Terjadwal", metricLabel: "Total Jam: 46 Jam", metricValue: "12 Karyawan", status: "APPROVED", rating: "4.8" },
    ];
  }

  if (code.startsWith("HRD-LEAVE")) {
    return [
      { id: "#LV-901", title: "Cuti Tahunan - Rizky Pratama", category: "3 Hari (14-16 Nov 2026)", metricLabel: "Sisa Kuota: 9 Hari", metricValue: "Menunggu HR", status: "PENDING", rating: "4.8" },
      { id: "#LV-902", title: "Izin Sakit (Surat Dokter) - Alya R.", category: "1 Hari (10 Nov 2026)", metricLabel: "Lampiran Valid", metricValue: "Disetujui", status: "APPROVED", rating: "5.0" },
      { id: "#LV-903", title: "Cuti Menikah - Dimas Anggara", category: "5 Hari (20-24 Nov 2026)", metricLabel: "Hak Cuti Khusus", metricValue: "Disetujui", status: "APPROVED", rating: "4.9" },
    ];
  }

  if (code.startsWith("HRD-PAY")) {
    return [
      { id: "#PAY-202611", title: `Payroll Periode November 2026 (${companyName})`, category: "183 Karyawan Aktif", metricLabel: "PPh 21 & BPJS Tersinkron", metricValue: "Rp 1.482.500.000", status: "READY", rating: "5.0" },
      { id: "#PAY-202610", title: `Payroll Periode Oktober 2026 (${companyName})`, category: "181 Karyawan Aktif", metricLabel: "Disbursed via Bank Payroll", metricValue: "Rp 1.460.200.000", status: "PAID", rating: "5.0" },
    ];
  }

  if (code.startsWith("ACC-")) {
    return [
      { id: "#ACC-8301", title: "Jurnal Penjualan & Diskon PromoHub", category: `GL Auto-Recon • ${companyName}`, metricLabel: "2,310 Transaksi", metricValue: "Rp 428.900.000", status: "POSTED", rating: "5.0" },
      { id: "#ACC-8302", title: "AP Invoice - Pembayaran Vendor Cloud & Lisensi", category: "Account Payable • Jatuh Tempo H-5", metricLabel: "14 Invoice", metricValue: "Rp 96.450.000", status: "PENDING", rating: "4.8" },
      { id: "#ACC-8303", title: "AR Receipt - Pelunasan Distributor Utama", category: "Account Receivable • Bank BCA", metricLabel: "28 Faktur", metricValue: "Rp 612.000.000", status: "CLEARED", rating: "4.9" },
      { id: "#ACC-8304", title: "Pajak PPN Keluaran & PPh 23 Bulanan", category: "Taxation • e-Faktur Ready", metricLabel: "Masa Pajak Nov", metricValue: "Rp 64.200.000", status: "VERIFIED", rating: "4.9" },
    ];
  }

  if (code.startsWith("CRM-")) {
    return [
      { id: "#CRM-401", title: "Enterprise Deal - PT Nusantara Retail", category: "Opportunity • Negotiation Stage", metricLabel: "Win Prob: 85%", metricValue: "Rp 850.000.000", status: "HOT_LEAD", rating: "5.0" },
      { id: "#CRM-402", title: "Quotation Q4 Bundle Omnichannel", category: "Quotation • Sent to Client", metricLabel: "120 Outlet", metricValue: "Rp 320.000.000", status: "OPEN", rating: "4.8" },
      { id: "#CRM-403", title: "Onboarding Distributor Jawa Timur", category: "Contact & Lead • Follow-Up", metricLabel: "PIC: Andi CRM", metricValue: "Rp 195.000.000", status: "ACTIVE", rating: "4.7" },
    ];
  }

  if (code.startsWith("PROMO-")) {
    return [
      { id: "#P-101", title: "Flash Sale 11.11 Elektronik & Gadget", category: `Omni-Channel • ${companyName}`, metricLabel: "3,420 Redemptions", metricValue: "Rp 145.000.000", status: "ACTIVE", rating: "5.0" },
      { id: "#P-102", title: "Payday Cashback Spesial Member Gold", category: `Tiered Promo • ${companyName}`, metricLabel: "2,180 Redemptions", metricValue: "Rp 88.500.000", status: "ACTIVE", rating: "4.9" },
      { id: "#P-104", title: "Bundle Hemat Akhir Tahun B2B", category: `Maker-Checker • ${companyName}`, metricLabel: "Menunggu Checker", metricValue: "Rp 120.000.000", status: "PENDING_APPROVAL", rating: "4.8" },
    ];
  }

  return [
    { id: `#${menu.menuCode}`, title: `${menu.menuName} (${companyName})`, category: `${menu.applicationName} • ${menu.moduleName}`, metricLabel: `Link: ${menu.menuLink}`, metricValue: "Aktif", status: "ACTIVE", rating: "5.0" },
  ];
}
