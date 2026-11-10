export type LangCode = "id" | "en";
export type CurrencyCode = "IDR" | "USD";
export type UserRole = "maker" | "checker";
export type PromoStatus = "all" | "active" | "scheduled" | "pending" | "paused" | "expired" | "rejected" | "draft";

export interface PromoHistoryItem {
  date: string;
  actor: string;
  action: string;
  note?: string;
}

export interface PromoItem {
  id: string;
  companyId?: number;
  companyCode?: string;
  code: string;
  name: string;
  localizedNames?: { id: string; en: string };
  description?: string;
  type: string;
  status: string;
  priority: number;
  version: number;
  startAt: string;
  endAt: string;
  expiresAt: string;
  daysUntilExpiry: number;
  baseCurrency: string;
  makerId: string;
  checkerId?: string | null;
  budgetCap: number;
  budgetUsed: number;
  redemptionCap: number;
  redemptionUsed: number;
  returnRate: number;
  roi: number;
  config?: Record<string, unknown>;
  history?: PromoHistoryItem[];
}

export interface ReturnEventItem {
  returnNo: string;
  orderId: string;
  returnedAt: string;
  promoId: string;
  actionText: { id: string; en: string };
  netRefund: number;
}

export interface AuditLogItem {
  id?: number;
  entityType: string;
  entityId: string;
  action: string;
  actor: string;
  actorRole?: string;
  reason?: string;
  createdAt: string;
}

export interface MenuPermissionFlags {
  view: number;
  add: number;
  edit: number;
  delete: number;
  approve: number;
}

export interface UserMenuItem {
  menuId: number;
  parentMenuId?: number | null;
  menuCode: string;
  menuName: string;
  menuLink: string;
  menuIndex?: number;
  iconName?: string;
  moduleId?: number;
  moduleName?: string;
  applicationId?: number;
  applicationCode?: string;
  applicationName?: string;
  permissions: MenuPermissionFlags;
}

export interface CompanyInfo {
  companyId: number;
  companyCode: string;
  companyName: string;
}

export interface AvailableUserInfo {
  username: string;
  name: string;
  companyId?: number | null;
  companyName: string;
  roleName: string;
}

export interface MultiTenantUserContext {
  userId: number;
  username: string;
  fullName: string;
  roleId: number;
  roleName: string;
  isSuperAdmin: boolean;
  userCompanyId?: number | null;
  effectiveCompanyId?: number | null;
  companyCode: string;
  companyName: string;
  menus: UserMenuItem[];
  promoPermissions: Record<string, MenuPermissionFlags>;
  companies: CompanyInfo[];
  availableUsers: AvailableUserInfo[];
}

export interface DashboardOverviewData {
  userContext?: MultiTenantUserContext;
  kpi: {
    activePromos: number;
    budgetUsedPercent: number;
    totalBudgetCap: number;
    totalBudgetUsed: number;
    totalRedemptions: number;
    pendingApprovals: number;
    expiringWithin7Days: number;
  };
  trend14d: number[];
  promotions: PromoItem[];
  returnEvents: ReturnEventItem[];
  auditLogs: AuditLogItem[];
  fxRateUsdIdr: number;
}

export const I18N: Record<string, [string, string]> = {
  overview: ["Ringkasan", "Overview"],
  promos: ["Daftar Promo", "Promotions"],
  appr: ["Approval", "Approvals"],
  sim: ["Simulator", "Simulator"],
  ret: ["Retur", "Returns"],
  aud: ["Audit Log", "Audit Log"],
  sub: ["Pantau seluruh promo dalam satu tampilan.", "Monitor every promotion at a glance."],
  search: ["Cari promo…", "Search promotions…"],
  kAct: ["Promo aktif", "Active promos"],
  kBud: ["Budget terpakai", "Budget used"],
  kRed: ["Redemption", "Redemptions"],
  kDis: ["Diskon diberikan", "Discount given"],
  kPen: ["Menunggu approval", "Pending approval"],
  kExp: ["Expired ≤ 7 hari", "Expiring ≤ 7 days"],
  trend: ["Tren redemption (14 hari)", "Redemption trend (14 days)"],
  burn: ["Budget burn per promo", "Budget burn by promo"],
  mix: ["Komposisi status", "Status mix"],
  alerts: ["Perlu perhatian", "Needs attention"],
  top: ["Promo terbaik (ROI)", "Top promos (ROI)"],
  all: ["Semua", "All"],
  name: ["Promo", "Promotion"],
  type: ["Tipe", "Type"],
  status: ["Status", "Status"],
  period: ["Periode", "Period"],
  exp: ["Expired date", "Expired date"],
  budget: ["Budget", "Budget"],
  red: ["Redemption", "Redemptions"],
  active: ["Aktif", "Active"],
  scheduled: ["Terjadwal", "Scheduled"],
  pending: ["Menunggu", "Pending"],
  paused: ["Jeda", "Paused"],
  expired: ["Expired", "Expired"],
  rejected: ["Ditolak", "Rejected"],
  draft: ["Draft", "Draft"],
  buy_x_get_y: ["Beli X Gratis Y", "Buy X Get Y"],
  bxgy: ["Beli X Gratis Y", "Buy X Get Y"],
  flash_sale: ["Flash sale", "Flash sale"],
  flash: ["Flash sale", "Flash sale"],
  payment_promo: ["Promo kartu", "Card promo"],
  pay: ["Promo kartu", "Card promo"],
  free_shipping: ["Gratis ongkir", "Free shipping"],
  ship: ["Gratis ongkir", "Free shipping"],
  tradein: ["Trade-in", "Trade-in"],
  new_user: ["Pengguna baru", "New user"],
  newu: ["Pengguna baru", "New user"],
  tiered_discount: ["Diskon bertingkat", "Tiered"],
  tier: ["Diskon bertingkat", "Tiered"],
  personalized_offer: ["Personal", "Personalized"],
  pers: ["Personal", "Personalized"],
  winback: ["Win-back", "Win-back"],
  win: ["Win-back", "Win-back"],
  discount_percent: ["Diskon %", "Percent Discount"],
  discount_fixed: ["Potongan Tetap", "Fixed Discount"],
  sum: ["Ringkasan aturan", "Rule summary"],
  lim: ["Batasan & kuota", "Limits & quota"],
  fund: ["Funding", "Funding"],
  rp: ["Kebijakan retur", "Return policy"],
  hist: ["Riwayat & approval", "History & approvals"],
  approve: ["Setujui", "Approve"],
  reject: ["Tolak", "Reject"],
  ext: ["Perpanjang expired date", "Extend expired date"],
  req: ["Ajukan perubahan", "Request change"],
  newExp: ["Expired date baru", "New expired date"],
  reason: ["Alasan (wajib)", "Reason (required)"],
  ok: ["Simpan", "Save"],
  cancel: ["Batal", "Cancel"],
  mkNote: [
    "Maker tidak dapat menyetujui/memperpanjang langsung; ajukan perubahan untuk ditinjau checker.",
    "Makers cannot approve/extend directly; submit a change request for a checker.",
  ],
  nA: ["Tidak ada promo yang menunggu.", "Nothing waiting for review."],
  none: ["Tidak ada hasil.", "No results."],
  created: ["dibuat", "created"],
  updated: ["diperbarui", "updated"],
  submitted: ["diajukan", "submitted"],
  approved: ["disetujui", "approved"],
  extended: ["diperpanjang", "extended"],
  rejectedH: ["ditolak", "rejected"],
  aBud: ["Budget ≥ 80% terpakai", "Budget ≥ 80% used"],
  aExp: ["akan expired dalam", "expires in"],
  aPen: ["menunggu keputusan checker", "awaiting checker decision"],
  aFx: ["Kurs IDR-USD diperbarui 08:00 WIB (16.000)", "IDR-USD rate updated 08:00 WIB (16,000)"],
  d: ["hari", "days"],
  ev: ["Peristiwa retur", "Return events"],
  ord: ["Pesanan", "Order"],
  act: ["Penyesuaian promo", "Promo adjustment"],
  refund: ["Refund", "Refund"],
  dtl: ["Aturan detail", "Detail"],
  use: ["Pemakaian", "Usage"],
  rr: ["Return rate", "Return rate"],
  roi: ["ROI", "ROI"],
  mk: ["Maker", "Maker"],
  ck: ["Checker", "Checker"],
  ex2: ["Maksimal 90 hari per perpanjangan.", "Max 90 days per extension."],
  bad: [
    "Tanggal harus maju dan maks. 90 hari, alasan wajib diisi.",
    "Date must move forward (max 90 days) and a reason is required.",
  ],
  newPromo: ["+ Buat Promo", "+ Create Promo"],
};

export function tr(key: string, lang: LangCode): string {
  const pair = I18N[key];
  if (!pair) return key;
  return lang === "id" ? pair[0] : pair[1];
}

export function formatMoney(
  amountIdr: number,
  currency: CurrencyCode,
  lang: LangCode,
  rate = 16000,
  compact = false
): string {
  const locale = lang === "id" ? "id-ID" : "en-US";
  if (currency === "IDR") {
    if (compact) {
      return "Rp" + new Intl.NumberFormat(locale, { notation: "compact", maximumFractionDigits: 1 }).format(amountIdr);
    }
    return "Rp" + Math.round(amountIdr).toLocaleString("id-ID");
  }
  const usd = amountIdr / (rate || 16000);
  if (compact) {
    return "$" + new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 1 }).format(usd);
  }
  return "$" + usd.toLocaleString("en-US", { maximumFractionDigits: usd < 100 ? 2 : 0 });
}

export function formatDateShort(isoOrDate: string | undefined, lang: LangCode): string {
  if (!isoOrDate) return "-";
  const datePart = isoOrDate.slice(0, 10);
  const d = new Date(datePart + "T00:00:00Z");
  if (Number.isNaN(d.getTime())) return isoOrDate;
  return d.toLocaleDateString(lang === "id" ? "id-ID" : "en-US", {
    day: "numeric",
    month: "short",
    year: "numeric",
    timeZone: "UTC",
  });
}
