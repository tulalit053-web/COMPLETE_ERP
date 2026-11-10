export interface DomainKpiCard {
  label: string;
  value: string;
  badge: string;
  badgeUp: boolean;
  subtitle: string;
  icon: string;
}

export interface DomainSegmentItem {
  icon: string;
  value: string;
  label: string;
  percent: number;
  color: string;
}

export interface DomainTableRow {
  id: string;
  name: string;
  sub: string;
  category: string;
  metric: string;
  rating: string;
  menuCode?: string;
}

export interface DomainDashboardConfig {
  code: string;
  title: string;
  subtitle: string;
  accentColor: string;
  chartTitle: string;
  chartPrimaryValue: string;
  chartBadge: string;
  chartTooltipTitle: string;
  chartTooltipPrimary: string;
  chartTooltipSecondary: string;
  svgPathPrimary: string;
  svgPathArea: string;
  svgPathSecondary: string;
  segmentBoxTitle: string;
  segments: [DomainSegmentItem, DomainSegmentItem, DomainSegmentItem];
  weekTitle: string;
  weekBars: Array<{ day: string; height: string; active?: boolean; val?: string }>;
  gaugeTitle: string;
  gaugePercent: number;
  gaugeSubtitle: string;
  tableTitle: string;
  tableHeaders: [string, string, string, string, string];
  tableRows: DomainTableRow[];
  kpis: [DomainKpiCard, DomainKpiCard, DomainKpiCard, DomainKpiCard];
}

export const DOMAIN_DASHBOARDS: Record<string, DomainDashboardConfig> = {
  HRD: {
    code: "HRD",
    title: "HRD & Payroll Dashboard",
    subtitle: "Monitoring real-time karyawan, tingkat kehadiran, pengajuan cuti, dan kesiapan penggajian.",
    accentColor: "#2563eb",
    kpis: [
      {
        label: "Total Karyawan Aktif",
        value: "183",
        badge: "▲ 4.5%",
        badgeUp: true,
        subtitle: "+8 karyawan baru kuartal ini",
        icon: "👥",
      },
      {
        label: "Kehadiran Hari Ini",
        value: "98.4%",
        badge: "▲ 2.1%",
        badgeUp: true,
        subtitle: "180 dari 183 hadir tepat waktu",
        icon: "🕒",
      },
      {
        label: "Pengajuan Cuti & Izin",
        value: "6",
        badge: "▼ 12.0%",
        badgeUp: true,
        subtitle: "2 menunggu persetujuan HR",
        icon: "🗓️",
      },
      {
        label: "Payroll Periode berjalan",
        value: "Rp 1,48 M",
        badge: "▲ Ready",
        badgeUp: true,
        subtitle: "PPh 21 & BPJS Ketenagakerjaan sinkron",
        icon: "💳",
      },
    ],
    chartTitle: "Indeks Produktivitas & Kehadiran Karyawan",
    chartPrimaryValue: "98.4%",
    chartBadge: "▲ 3.8%",
    chartTooltipTitle: "18 Nov 2026",
    chartTooltipPrimary: "180 Hadir Tepat Waktu",
    chartTooltipSecondary: "3 Cuti Terjadwal",
    svgPathArea:
      "M35,76 L85,70 L135,58 L185,62 L235,48 L285,36 L335,40 L385,32 L435,26 L495,20 L495,115 L35,115 Z",
    svgPathPrimary:
      "M35,76 L85,70 L135,58 L185,62 L235,48 L285,36 L335,40 L385,32 L435,26 L495,20",
    svgPathSecondary:
      "M35,92 L85,88 L135,80 L185,84 L235,74 L285,68 L335,70 L385,64 L435,58 L495,50",
    segmentBoxTitle: "Komposisi Status Kepegawaian",
    segments: [
      {
        icon: "🏢",
        value: "138",
        label: "Karyawan Tetap (Permanent)",
        percent: 75,
        color: "#2563eb",
      },
      {
        icon: "📄",
        value: "32",
        label: "Karyawan Kontrak (PKWT)",
        percent: 18,
        color: "#10b981",
      },
      {
        icon: "🌱",
        value: "13",
        label: "Masa Percobaan (Probation)",
        percent: 7,
        color: "#f59e0b",
      },
    ],
    weekTitle: "Tingkat Kehadiran Mingguan",
    weekBars: [
      { day: "Sun", height: "25%" },
      { day: "Mon", height: "84%" },
      { day: "Tue", height: "96%", active: true, val: "99.2%" },
      { day: "Wed", height: "88%" },
      { day: "Thu", height: "90%" },
      { day: "Fri", height: "86%" },
      { day: "Sat", height: "35%" },
    ],
    gaugeTitle: "Retensi & Kepuasan SDM",
    gaugePercent: 92,
    gaugeSubtitle: "Target tahunan HR ≥ 85%",
    tableTitle: "Aktivitas SDM, Kehadiran & Cuti Terkini",
    tableHeaders: ["ID", "NAMA KARYAWAN / AGENDA", "DIVISI & STATUS", "METRIK / GAJI", "RATING"],
    tableRows: [
      {
        id: "#EMP-301",
        name: "Dewi Lestari — HR Manager",
        sub: "Human Capital • Permanent",
        category: "Masa Kerja 4.2 Thn",
        metric: "Hadir 100%",
        rating: "5.0",
        menuCode: "HRD-EMP-LIST",
      },
      {
        id: "#EMP-302",
        name: "Rizky Pratama — Sr. Software Engineer",
        sub: "Engineering • Pengajuan Cuti 3 Hari",
        category: "14–16 Nov 2026",
        metric: "Menunggu HR",
        rating: "4.9",
        menuCode: "HRD-LEAVE-LIST",
      },
      {
        id: "#ATT-110",
        name: "Rekap Presensi Shift Pagi Head Office",
        sub: "Check-in rata-rata 07:54 WIB",
        category: "142 / 145 Karyawan",
        metric: "98.4% On-Time",
        rating: "5.0",
        menuCode: "HRD-ATT-LIST",
      },
      {
        id: "#PAY-11",
        name: "Batch Payroll & PPh 21 November 2026",
        sub: "183 Slip Gaji Terkalkulasi Otomatis",
        category: "Payroll Process",
        metric: "Rp 1.482.500.000",
        rating: "5.0",
        menuCode: "HRD-PAY-LIST",
      },
    ],
  },

  ACC: {
    code: "ACC",
    title: "Accounting & Finance Dashboard",
    subtitle: "Ringkasan posisi kas & bank, buku besar (GL), piutang (AR), hutang (AP), dan perpajakan.",
    accentColor: "#2563eb",
    kpis: [
      {
        label: "Saldo Kas & Bank",
        value: "Rp 2,41 M",
        badge: "▲ 14.2%",
        badgeUp: true,
        subtitle: "3 rekening operasional terhubung",
        icon: "🏦",
      },
      {
        label: "Piutang Usaha (AR)",
        value: "Rp 612 Jt",
        badge: "▲ 8.4%",
        badgeUp: true,
        subtitle: "28 faktur pelanggan aktif",
        icon: "📥",
      },
      {
        label: "Hutang Jatuh Tempo (AP)",
        value: "Rp 96,4 Jt",
        badge: "▼ 5.2%",
        badgeUp: false,
        subtitle: "14 invoice jatuh tempo < 7 hari",
        icon: "📤",
      },
      {
        label: "Jurnal Umum Terposting",
        value: "2.310",
        badge: "▲ 100%",
        badgeUp: true,
        subtitle: "Termasuk jurnal diskon PromoHub",
        icon: "📘",
      },
    ],
    chartTitle: "Arus Kas Bersih & Laba Operasional (Net Profit)",
    chartPrimaryValue: "Rp 446,7 Jt",
    chartBadge: "▲ 24.4%",
    chartTooltipTitle: "18 Nov 2026",
    chartTooltipPrimary: "Rp 42,8 Jt bulan ini",
    chartTooltipSecondary: "Rp 31,2 Jt bulan lalu",
    svgPathArea:
      "M35,84 L85,80 L135,54 L185,68 L235,58 L285,36 L335,44 L385,52 L435,28 L495,18 L495,115 L35,115 Z",
    svgPathPrimary:
      "M35,84 L85,80 L135,54 L185,68 L235,58 L285,36 L335,44 L385,52 L435,28 L495,18",
    svgPathSecondary:
      "M35,96 L85,92 L135,78 L185,84 L235,76 L285,62 L335,68 L385,66 L435,50 L495,44",
    segmentBoxTitle: "Distribusi Likuiditas & Modal Kerja",
    segments: [
      {
        icon: "🏦",
        value: "Rp 1,42 M",
        label: "Kas & Bank Operasional",
        percent: 59,
        color: "#2563eb",
      },
      {
        icon: "📈",
        value: "Rp 612 Jt",
        label: "Piutang Tertagih (AR)",
        percent: 26,
        color: "#10b981",
      },
      {
        icon: "📦",
        value: "Rp 378 Jt",
        label: "Nilai Persediaan (Inventory)",
        percent: 15,
        color: "#f59e0b",
      },
    ],
    weekTitle: "Volume Transaksi Jurnal Harian",
    weekBars: [
      { day: "Sun", height: "30%" },
      { day: "Mon", height: "68%" },
      { day: "Tue", height: "94%", active: true, val: "482" },
      { day: "Wed", height: "64%" },
      { day: "Thu", height: "72%" },
      { day: "Fri", height: "80%" },
      { day: "Sat", height: "40%" },
    ],
    gaugeTitle: "Rekonsiliasi Bank & Pajak",
    gaugePercent: 88,
    gaugeSubtitle: "Target tutup buku H+3",
    tableTitle: "Jurnal Umum, Invoice AP/AR & Pajak Terkini",
    tableHeaders: ["NO DOKUMEN", "DESKRIPSI TRANSAKSI", "MODUL AKUNTANSI", "NOMINAL", "STATUS"],
    tableRows: [
      {
        id: "#GL-8301",
        name: "Jurnal Penjualan & Beban Diskon PromoHub",
        sub: "Auto-Journal dari Engine Promo",
        category: "General Ledger",
        metric: "Rp 428.900.000",
        rating: "Posted",
        menuCode: "ACC-GL-JOURNAL",
      },
      {
        id: "#AR-8302",
        name: "Pelunasan Piutang Distributor Utama",
        sub: "Bank BCA Corporate • Terverifikasi",
        category: "Account Receivable",
        metric: "Rp 612.000.000",
        rating: "Cleared",
        menuCode: "ACC-AR-RECEIPT",
      },
      {
        id: "#AP-8303",
        name: "Tagihan Vendor Infrastruktur & Lisensi",
        sub: "Jatuh tempo 15 Nov 2026",
        category: "Account Payable",
        metric: "Rp 96.450.000",
        rating: "Pending",
        menuCode: "ACC-AP-INVOICE",
      },
      {
        id: "#TAX-8304",
        name: "Rekapitulasi PPN Keluaran & PPh 23",
        sub: "Masa Pajak November 2026",
        category: "Taxation",
        metric: "Rp 64.200.000",
        rating: "Verified",
        menuCode: "ACC-TAX-VAT",
      },
    ],
  },

  CRM: {
    code: "CRM",
    title: "CRM & Sales Pipeline Dashboard",
    subtitle: "Pantau akuisisi prospek (Lead), nilai peluang (Opportunity), Quotation, dan kampanye promo.",
    accentColor: "#2563eb",
    kpis: [
      {
        label: "Total Prospek (Leads)",
        value: "148",
        badge: "▲ 18.5%",
        badgeUp: true,
        subtitle: "32 prospek baru minggu ini",
        icon: "🎯",
      },
      {
        label: "Nilai Pipeline Aktif",
        value: "Rp 1,36 M",
        badge: "▲ 12.4%",
        badgeUp: true,
        subtitle: "9 deal korporasi tahap negosiasi",
        icon: "💼",
      },
      {
        label: "Quotation Terkirim",
        value: "24",
        badge: "▲ 6.8%",
        badgeUp: true,
        subtitle: "7 menunggu PO pelanggan",
        icon: "📄",
      },
      {
        label: "Win Rate Konversi",
        value: "68.0%",
        badge: "▲ 5.4%",
        badgeUp: true,
        subtitle: "Didorong bundel promo aktif",
        icon: "🏆",
      },
    ],
    chartTitle: "Tren Nilai Konversi Penjualan & Pipeline CRM",
    chartPrimaryValue: "Rp 1,36 M",
    chartBadge: "▲ 21.8%",
    chartTooltipTitle: "18 Nov 2026",
    chartTooltipPrimary: "Rp 195 Jt Deal Closed",
    chartTooltipSecondary: "14 Lead Qualified",
    svgPathArea:
      "M35,88 L85,78 L135,64 L185,56 L235,48 L285,42 L335,34 L385,38 L435,24 L495,16 L495,115 L35,115 Z",
    svgPathPrimary:
      "M35,88 L85,78 L135,64 L185,56 L235,48 L285,42 L335,34 L385,38 L435,24 L495,16",
    svgPathSecondary:
      "M35,98 L85,92 L135,84 L185,78 L235,72 L285,66 L335,60 L385,62 L435,48 L495,42",
    segmentBoxTitle: "Segmentasi Pelanggan B2B & Retail",
    segments: [
      {
        icon: "🏪",
        value: "2,884",
        label: "Retailers Aktif",
        percent: 58,
        color: "#2563eb",
      },
      {
        icon: "🚚",
        value: "1,432",
        label: "Distributors Regional",
        percent: 29,
        color: "#10b981",
      },
      {
        icon: "🏭",
        value: "562",
        label: "Wholesalers & Key Account",
        percent: 13,
        color: "#f59e0b",
      },
    ],
    weekTitle: "Aktivitas Follow-Up & Kunjungan Sales",
    weekBars: [
      { day: "Sun", height: "35%" },
      { day: "Mon", height: "62%" },
      { day: "Tue", height: "92%", active: true, val: "8,162" },
      { day: "Wed", height: "58%" },
      { day: "Thu", height: "74%" },
      { day: "Fri", height: "66%" },
      { day: "Sat", height: "48%" },
    ],
    gaugeTitle: "Repeat Customer Rate",
    gaugePercent: 68,
    gaugeSubtitle: "On track for 80% target",
    tableTitle: "Peluang Penjualan (Opportunity) & Quotation Teratas",
    tableHeaders: ["ID DEAL", "PELANGGAN / PROYEK", "TAHAPAN PIPELINE", "ESTIMASI NILAI", "SKOR"],
    tableRows: [
      {
        id: "#CRM-401",
        name: "PT Nusantara Retail — Kontrak Tahunan",
        sub: "Negotiation Stage • Win Prob 85%",
        category: "Opportunity",
        metric: "Rp 850.000.000",
        rating: "5.0",
        menuCode: "CRM-OPP-LIST",
      },
      {
        id: "#CRM-402",
        name: "Quotation Bundle Omnichannel Q4",
        sub: "120 Outlet Cabang Nasional",
        category: "Quotation",
        metric: "Rp 320.000.000",
        rating: "4.9",
        menuCode: "CRM-QUO-LIST",
      },
      {
        id: "#CRM-403",
        name: "Onboarding Distributor Jawa Timur",
        sub: "PIC: Andi CRM • Follow-up Kunjungan",
        category: "Lead Management",
        metric: "Rp 195.000.000",
        rating: "4.8",
        menuCode: "CRM-LEAD-LIST",
      },
    ],
  },

  PROMO: {
    code: "PROMO",
    title: "PromoHub Governance Dashboard",
    subtitle: "Ringkasan performa kampanye promosi, serapan anggaran (budget cap), dan antrean Maker-Checker.",
    accentColor: "#2563eb",
    kpis: [
      {
        label: "Kampanye Promo Aktif",
        value: "5 Promo",
        badge: "▲ 15.5%",
        badgeUp: true,
        subtitle: "2 promo berakhir dalam 7 hari",
        icon: "🏷️",
      },
      {
        label: "Serapan Budget Promo",
        value: "52.3%",
        badge: "▲ Optimal",
        badgeUp: true,
        subtitle: "Rp 287,5 Jt dari plafon Rp 550 Jt",
        icon: "💰",
      },
      {
        label: "Total Klaim (Redemptions)",
        value: "11,268",
        badge: "▲ 18.4%",
        badgeUp: true,
        subtitle: "Omnichannel POS, Web & App",
        icon: "🎟️",
      },
      {
        label: "Antrean Approval Checker",
        value: "1 Pending",
        badge: "⚡ Action",
        badgeUp: false,
        subtitle: "Menunggu otorisasi kepala divisi",
        icon: "🛡️",
      },
    ],
    chartTitle: "Tren Klaim Diskon & Efektivitas Kampanye Promo",
    chartPrimaryValue: "Rp 287,5 Jt",
    chartBadge: "▲ 22.4%",
    chartTooltipTitle: "18 Nov 2026",
    chartTooltipPrimary: "1.480 Klaim Hari Ini",
    chartTooltipSecondary: "Konversi Keranjang +31%",
    svgPathArea:
      "M35,82 L85,74 L135,60 L185,66 L235,50 L285,34 L335,42 L385,30 L435,22 L495,16 L495,115 L35,115 Z",
    svgPathPrimary:
      "M35,82 L85,74 L135,60 L185,66 L235,50 L285,34 L335,42 L385,30 L435,22 L495,16",
    svgPathSecondary:
      "M35,96 L85,90 L135,82 L185,84 L235,74 L285,64 L335,68 L385,58 L435,48 L495,42",
    segmentBoxTitle: "Alokasi Anggaran per Kategori Promo",
    segments: [
      {
        icon: "⚡",
        value: "Rp 145 Jt",
        label: "Flash Sale & Diskon Langsung",
        percent: 50,
        color: "#2563eb",
      },
      {
        icon: "🎁",
        value: "Rp 88,5 Jt",
        label: "Cashback & Tier Member",
        percent: 31,
        color: "#10b981",
      },
      {
        icon: "📦",
        value: "Rp 54 Jt",
        label: "Bundle B2B & GWP",
        percent: 19,
        color: "#f59e0b",
      },
    ],
    weekTitle: "Trafik Klaim Voucher Mingguan",
    weekBars: [
      { day: "Sun", height: "64%" },
      { day: "Mon", height: "52%" },
      { day: "Tue", height: "95%", active: true, val: "3,420" },
      { day: "Wed", height: "60%" },
      { day: "Thu", height: "70%" },
      { day: "Fri", height: "82%" },
      { day: "Sat", height: "78%" },
    ],
    gaugeTitle: "Efisiensi ROI Kampanye",
    gaugePercent: 84,
    gaugeSubtitle: "Target ROAS 4.2x tercapai",
    tableTitle: "Kampanye Promo Unggulan & Status Approval",
    tableHeaders: ["KODE", "NAMA KAMPANYE PROMO", "TIPE & KANAL", "REALISASI BUDGET", "STATUS"],
    tableRows: [
      {
        id: "P-101",
        name: "Flash Sale 11.11 Elektronik & Gadget",
        sub: "3.420 Redemptions • Web & App",
        category: "Percentage Discount",
        metric: "Rp 145.000.000",
        rating: "Active",
        menuCode: "PROMO-LIST",
      },
      {
        id: "P-102",
        name: "Payday Cashback Spesial Member Gold",
        sub: "2.180 Redemptions • Semua Kanal",
        category: "Tiered Cashback",
        metric: "Rp 88.500.000",
        rating: "Active",
        menuCode: "PROMO-LIST",
      },
      {
        id: "P-104",
        name: "Bundle Hemat Akhir Tahun B2B",
        sub: "Diajukan oleh Maker • Menunggu Checker",
        category: "Bundle Promo",
        metric: "Rp 120.000.000",
        rating: "Pending",
        menuCode: "PROMO-APPROVAL",
      },
    ],
  },
};

export function resolveDashboardConfig(
  selectedViewCode: string,
  subscribedCodes: string[]
): DomainDashboardConfig {
  if (selectedViewCode !== "AUTO" && DOMAIN_DASHBOARDS[selectedViewCode]) {
    return DOMAIN_DASHBOARDS[selectedViewCode];
  }
  if (subscribedCodes.length === 1 && DOMAIN_DASHBOARDS[subscribedCodes[0]]) {
    return DOMAIN_DASHBOARDS[subscribedCodes[0]];
  }
  // Jika punya ACC + CRM + PROMO (seperti budi.santoso) tapi memilih tampilan utama:
  // tampilkan gabungan eksekutif (berbasis kinerja bisnis & seluruh aplikasi yang dimiliki)
  if (subscribedCodes.includes("ACC") && subscribedCodes.includes("CRM")) {
    return {
      ...DOMAIN_DASHBOARDS.CRM,
      code: "EXEC",
      title: "Executive Multi-Application Dashboard",
      subtitle: `Ringkasan terpadu lintas aplikasi (${subscribedCodes.join(
        ", "
      )}) sesuai hak akses perusahaan Anda.`,
      kpis: [
        {
          label: "Pendapatan & Kas (ACC)",
          value: "Rp 2,41 M",
          badge: "▲ 15.5%",
          badgeUp: true,
          subtitle: "2.310 jurnal otomatis terposting",
          icon: "🏛️",
        },
        {
          label: "Pipeline Penjualan (CRM)",
          value: "Rp 1,36 M",
          badge: "▲ 12.4%",
          badgeUp: true,
          subtitle: "148 prospek & 24 quotation aktif",
          icon: "🤝",
        },
        {
          label: "Klaim Kampanye (PROMO)",
          value: "11,268",
          badge: "▲ 18.4%",
          badgeUp: true,
          subtitle: "5 promo aktif • 52% budget terpakai",
          icon: "🏷️",
        },
        {
          label: "Antrean Persetujuan",
          value: "4 Dokumen",
          badge: "⚡ Checker",
          badgeUp: true,
          subtitle: "Siap diotorisasi oleh Role Anda",
          icon: "✅",
        },
      ],
      chartTitle: "Total Profit & Performa Bisnis Terpadu",
      chartPrimaryValue: "Rp 446,7 Jt",
      tableTitle: "Aktivitas Lintas Aplikasi (Accounting, CRM & PromoHub)",
      tableHeaders: ["KODE", "AKTIVITAS / DOKUMEN", "MODUL APLIKASI", "NILAI / METRIK", "STATUS"],
      tableRows: [
        DOMAIN_DASHBOARDS.ACC.tableRows[0],
        DOMAIN_DASHBOARDS.CRM.tableRows[0],
        DOMAIN_DASHBOARDS.PROMO.tableRows[0],
        DOMAIN_DASHBOARDS.PROMO.tableRows[2],
      ],
    };
  }

  const firstMatch = subscribedCodes.find((c) => DOMAIN_DASHBOARDS[c]);
  return firstMatch ? DOMAIN_DASHBOARDS[firstMatch] : DOMAIN_DASHBOARDS.CRM;
}
