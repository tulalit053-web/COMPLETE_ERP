# Spesifikasi Promo Engine (Config-Driven)

> Dokumen ini mendefinisikan semua jenis promo, parameter, aturan, dan struktur data untuk aplikasi promo.
> Tujuan utama: **promo baru cukup dibuat lewat konfigurasi (data), tanpa mengubah kode.**

---

## Daftar Isi

1. [Tujuan & Ruang Lingkup](#1-tujuan--ruang-lingkup)
2. [Prinsip Desain](#2-prinsip-desain)
3. [Model Konseptual](#3-model-konseptual)
4. [Skema Promo Umum (Master Schema)](#4-skema-promo-umum-master-schema)
5. [Katalog Fakta & Operator (Condition Engine)](#5-katalog-fakta--operator-condition-engine)
6. [Katalog Benefit](#6-katalog-benefit)
7. [Katalog Tipe Promo](#7-katalog-tipe-promo)
8. [Batasan (Limits & Guardrails)](#8-batasan-limits--guardrails)
9. [Stacking, Prioritas & Konflik](#9-stacking-prioritas--konflik)
10. [Urutan Kalkulasi (Pricing Pipeline)](#10-urutan-kalkulasi-pricing-pipeline)
11. [Pendanaan Promo (Funding)](#11-pendanaan-promo-funding)
12. [Lifecycle & Approval](#12-lifecycle--approval)
13. [Desain Database](#13-desain-database)
14. [Desain API](#14-desain-api)
15. [Edge Case Penting](#15-edge-case-penting)
16. [Anti-Fraud & Abuse](#16-anti-fraud--abuse)
17. [Analitik & KPI](#17-analitik--kpi)
18. [Checklist Testing](#18-checklist-testing)
19. [Panduan Marketing: Memilih Mekanisme Promo](#19-panduan-marketing-memilih-mekanisme-promo)
20. [Roadmap Implementasi](#20-roadmap-implementasi)
21. [Glosarium](#21-glosarium)

---

## 1. Tujuan & Ruang Lingkup

**Tujuan**
- Menyediakan satu mesin promo yang dapat dipakai lintas channel (web, app, kasir/POS, marketplace).
- Tim marketing dapat membuat, mengubah, menjadwalkan, dan menghentikan promo lewat dashboard/konfigurasi.
- Tim engineering tidak perlu deploy ulang untuk setiap promo baru.

**Dalam ruang lingkup**
- Diskon (persen, nominal, harga tetap)
- Buy X Get Y (termasuk Buy 1 Get 1)
- Bundling dan mix & match
- Tiered / volume discount
- Promo metode pembayaran (kartu kredit, debit, e-wallet, cicilan)
- Buyback / trade-in
- Voucher / kode kupon
- Gratis ongkir
- Cashback dan poin loyalty
- Gift with purchase
- Flash sale
- Promo member / tier / ulang tahun / pengguna baru
- Referral

**Di luar ruang lingkup (dokumen ini)**
- Payment gateway, settlement dengan bank, dan sistem akuntansi (hanya disediakan titik integrasi)
- CRM dan campaign messaging (hanya disediakan event/trigger)

---

## 2. Prinsip Desain

| # | Prinsip | Penjelasan |
|---|---------|------------|
| 1 | **Config over code** | Semua nilai (persen, nominal, SKU, tanggal, kuota) berasal dari konfigurasi, bukan hardcode. |
| 2 | **Komposisi** | Promo = *Scope + Condition + Benefit + Limit + Schedule*. Tipe baru = kombinasi baru dari blok yang ada. |
| 3 | **Deklaratif** | Promo menjelaskan *apa* aturannya, engine yang menentukan *bagaimana* menghitungnya. |
| 4 | **Deterministik** | Input yang sama menghasilkan hasil yang sama. Urutan kalkulasi dan resolusi konflik terdefinisi jelas. |
| 5 | **Dapat diaudit** | Setiap promo yang diterapkan tercatat: promo apa, nilai berapa, versi aturan yang mana. |
| 6 | **Versioning** | Perubahan promo menghasilkan versi baru; transaksi lama tetap merujuk versi saat transaksi terjadi. |
| 7 | **Aman secara default** | Ada batas maksimal diskon, kuota, dan validasi margin sebelum promo aktif. |
| 8 | **Dapat disimulasikan** | Ada mode *dry-run* untuk menguji promo terhadap keranjang contoh sebelum dipublikasikan. |
| 9 | **Idempoten** | Redeem/rollback aman dipanggil ulang tanpa menggandakan efek. |
| 10 | **Multi-currency & timezone aware** | Mata uang, pembulatan, dan zona waktu menjadi parameter. |

---

## 3. Model Konseptual

```
PROMO
 ├── Schedule     → kapan berlaku
 ├── Scope        → berlaku untuk produk/kategori/channel/toko apa
 ├── Conditions   → syarat (keranjang, pelanggan, pembayaran, waktu, dll.)
 ├── Benefit      → apa yang didapat (diskon, barang gratis, cashback, dll.)
 ├── Limits       → kuota, batas per user, batas budget, batas maksimal diskon
 ├── Stacking     → boleh digabung dengan promo lain atau tidak
 ├── Funding      → siapa yang menanggung biaya promo
 └── Display      → teks, banner, badge, syarat & ketentuan
```

**Alur evaluasi singkat**

```
Cart + Customer + Context
        │
        ▼
1. Ambil kandidat promo aktif (schedule, status, channel)
2. Filter scope (item mana yang eligible)
3. Evaluasi conditions
4. Cek limits (kuota, per user, budget)
5. Hitung benefit
6. Resolusi stacking & prioritas
7. Hasil akhir: harga, rincian promo, alasan promo yang tidak berlaku
```

---

## 4. Skema Promo Umum (Master Schema)

Semua promo memakai struktur dasar yang sama. Contoh lengkap (JSON):

```json
{
  "id": "promo_001",
  "code": "BOGO-JUN-2026",
  "name": "Beli 1 Gratis 1 Kaos Basic",
  "description": "Beli 1 kaos basic, dapat 1 kaos basic gratis (harga terendah).",
  "type": "buy_x_get_y",
  "status": "active",
  "priority": 100,
  "version": 3,

  "schedule": {
    "start_at": "2026-06-01T00:00:00",
    "end_at": "2026-06-30T23:59:59",
    "timezone": "Asia/Jakarta",
    "recurrence": {
      "days_of_week": ["FRI", "SAT", "SUN"],
      "time_windows": [{ "from": "10:00", "to": "22:00" }]
    }
  },

  "scope": {
    "channels": ["web", "app", "pos"],
    "stores": { "include": ["ALL"], "exclude": ["STORE-099"] },
    "items": {
      "include": { "categories": ["CAT-TSHIRT"], "brands": [], "skus": [], "tags": ["basic"] },
      "exclude": { "skus": ["SKU-LIMITED-01"], "tags": ["already_discounted"] }
    }
  },

  "conditions": {
    "all": [
      { "fact": "cart.eligible_item_qty", "op": ">=", "value": 2 }
    ]
  },

  "benefit": {
    "kind": "buy_x_get_y",
    "params": {
      "buy_qty": 1,
      "get_qty": 1,
      "get_discount_percent": 100,
      "get_item_selection": "lowest_price",
      "repeat": true,
      "max_repeat": 5
    }
  },

  "limits": {
    "total_redemptions": 1000,
    "per_user_redemptions": 3,
    "per_order_redemptions": 5,
    "budget_cap": 50000000,
    "max_discount_per_order": 500000,
    "min_margin_percent": 10
  },

  "stacking": {
    "mode": "exclusive_in_group",
    "group": "item_discount",
    "can_combine_with": ["free_shipping", "payment_promo"],
    "cannot_combine_with": ["voucher"]
  },

  "funding": [
    { "party": "merchant", "share_percent": 70 },
    { "party": "brand", "share_percent": 30 }
  ],

  "display": {
    "badge": "Beli 1 Gratis 1",
    "banner_url": "https://cdn.example.com/bogo.jpg",
    "short_text": "Beli 1 Gratis 1 semua kaos basic",
    "terms_and_conditions": "Diskon diberikan pada item dengan harga terendah..."
  },

  "metadata": {
    "created_by": "marketing.user",
    "approved_by": "head.marketing",
    "campaign_id": "CMP-JUN-2026",
    "tags": ["seasonal", "apparel"]
  }
}
```

### Penjelasan blok utama

| Blok | Fungsi | Wajib? |
|------|--------|--------|
| `id`, `code`, `name`, `description` | Identitas promo | Ya |
| `type` | Jenis promo (untuk klasifikasi/pelaporan) | Ya |
| `status` | `draft`, `pending_approval`, `scheduled`, `active`, `paused`, `expired`, `cancelled` | Ya |
| `priority` | Angka lebih besar = diproses lebih dulu | Ya |
| `version` | Naik setiap perubahan aturan | Ya |
| `schedule` | Periode, zona waktu, jadwal berulang | Ya |
| `scope` | Produk, channel, toko yang tercakup | Ya |
| `conditions` | Syarat tambahan (pohon aturan) | Opsional |
| `benefit` | Hadiah/diskon yang diberikan | Ya |
| `limits` | Batas kuota/budget/diskon | Sangat disarankan |
| `stacking` | Aturan penggabungan | Ya |
| `funding` | Pembagian biaya | Opsional |
| `display` | Teks & visual | Opsional |

---

## 5. Katalog Fakta & Operator (Condition Engine)

Condition ditulis sebagai **pohon aturan** dengan operator logika `all` (AND), `any` (OR), dan `not`.

```json
{
  "all": [
    { "fact": "cart.subtotal", "op": ">=", "value": 500000 },
    { "any": [
      { "fact": "customer.tier", "op": "in", "value": ["GOLD", "PLATINUM"] },
      { "fact": "customer.is_new", "op": "==", "value": true }
    ]},
    { "not": { "fact": "payment.method", "op": "==", "value": "cod" } }
  ]
}
```

### 5.1 Operator

| Operator | Arti |
|----------|------|
| `==`, `!=` | Sama / tidak sama |
| `>`, `>=`, `<`, `<=` | Perbandingan angka/tanggal |
| `in`, `not_in` | Termasuk / tidak dalam daftar |
| `between` | Dalam rentang `[min, max]` |
| `contains`, `not_contains` | Daftar/teks mengandung nilai |
| `starts_with` | Awalan teks (contoh: BIN kartu) |
| `matches` | Regex (pakai hati-hati) |
| `exists`, `not_exists` | Data tersedia / tidak |

### 5.2 Katalog Fakta (Facts)

**Keranjang (`cart.*`)**

| Fact | Tipe | Keterangan |
|------|------|------------|
| `cart.subtotal` | number | Total harga sebelum diskon |
| `cart.eligible_subtotal` | number | Subtotal item yang masuk scope promo |
| `cart.item_qty` | number | Total kuantitas semua item |
| `cart.eligible_item_qty` | number | Kuantitas item eligible |
| `cart.distinct_sku_count` | number | Jumlah SKU unik |
| `cart.contains_sku` | list | Daftar SKU di keranjang |
| `cart.contains_category` | list | Daftar kategori di keranjang |
| `cart.shipping_fee` | number | Ongkos kirim |
| `cart.weight` | number | Total berat |

**Pelanggan (`customer.*`)**

| Fact | Tipe | Keterangan |
|------|------|------------|
| `customer.id` | string | ID pelanggan |
| `customer.is_new` | boolean | Belum pernah transaksi |
| `customer.tier` | string | Silver/Gold/Platinum, dll. |
| `customer.segment` | list | Segmen CRM |
| `customer.birthday_month` | number | Bulan lahir |
| `customer.order_count` | number | Jumlah order sebelumnya |
| `customer.lifetime_spend` | number | Total belanja seumur hidup |
| `customer.days_since_last_order` | number | Untuk promo win-back |
| `customer.region` | string | Provinsi/kota |
| `customer.is_employee` | boolean | Promo karyawan |

**Pembayaran (`payment.*`)**

| Fact | Tipe | Keterangan |
|------|------|------------|
| `payment.method` | string | `credit_card`, `debit_card`, `ewallet`, `va`, `qris`, `cod`, `paylater` |
| `payment.provider` | string | Nama bank/e-wallet (BCA, Mandiri, OVO, dll.) |
| `payment.card_bin` | string | 6-8 digit pertama kartu |
| `payment.card_network` | string | Visa/Mastercard/JCB |
| `payment.card_type` | string | `credit` / `debit` |
| `payment.installment_tenor` | number | Tenor cicilan (bulan) |

**Konteks (`context.*`)**

| Fact | Tipe | Keterangan |
|------|------|------------|
| `context.channel` | string | web/app/pos/marketplace |
| `context.store_id` | string | Toko/outlet |
| `context.platform` | string | iOS/Android/Web |
| `context.now` | datetime | Waktu transaksi |
| `context.coupon_code` | string | Kode yang dimasukkan |
| `context.utm_source` | string | Sumber traffic |
| `context.is_first_order_in_app` | boolean | Pesanan pertama di app |

**Trade-in / Buyback (`tradein.*`)**

| Fact | Tipe | Keterangan |
|------|------|------------|
| `tradein.device_category` | string | Kategori barang lama |
| `tradein.brand` | string | Merek |
| `tradein.model` | string | Model |
| `tradein.condition_grade` | string | A/B/C/D |
| `tradein.appraised_value` | number | Nilai taksiran |
| `tradein.age_months` | number | Usia barang |

> **Catatan ekstensibilitas:** fakta baru bisa ditambahkan lewat *Fact Registry* (nama, tipe, sumber data) tanpa mengubah engine.

---

## 6. Katalog Benefit

Setiap benefit punya `kind` dan `params`.

| `kind` | Deskripsi | Parameter utama |
|--------|-----------|-----------------|
| `discount_percent` | Diskon persen | `percent`, `apply_to` (item/cart/shipping), `max_amount` |
| `discount_fixed` | Potongan nominal | `amount`, `apply_to`, `distribute` (proporsional/rata) |
| `fixed_price` | Harga khusus | `price`, `per` (item/bundle) |
| `buy_x_get_y` | Beli X dapat Y | `buy_qty`, `get_qty`, `get_discount_percent`, `get_item_selection`, `repeat`, `max_repeat` |
| `free_item` | Barang gratis | `sku`/`item_pool`, `qty`, `auto_add` |
| `free_shipping` | Gratis ongkir | `max_shipping_subsidy`, `shipping_methods` |
| `cashback` | Dana kembali | `percent`/`amount`, `max_amount`, `destination` (wallet/rekening/kartu), `payout_delay_days` |
| `points` | Poin loyalty | `points`/`multiplier`, `max_points`, `expiry_days` |
| `tiered_discount` | Diskon bertingkat | `tiers[]`, `tier_basis` (qty/amount), `mode` (cumulative/highest) |
| `bundle_price` | Harga paket | `bundle_items[]`, `bundle_price` |
| `installment_subsidy` | Bunga cicilan 0% | `tenors[]`, `subsidy_percent`, `admin_fee` |
| `tradein_credit` | Nilai tukar tambah | `credit_source` (appraisal/fixed), `bonus_amount`, `bonus_percent`, `max_credit` |
| `gift` | Hadiah fisik/digital | `gift_sku`, `qty`, `stock_pool` |
| `voucher_issue` | Menerbitkan voucher baru | `voucher_template_id`, `valid_days` |

**Parameter umum benefit**

| Parameter | Fungsi |
|-----------|--------|
| `apply_to` | `item`, `cart`, `shipping`, `payment` |
| `rounding` | `none`, `round`, `floor`, `ceil` dan `rounding_unit` (mis. 100) |
| `min_price_floor` | Harga akhir item tidak boleh di bawah nilai ini |
| `max_discount` | Batas atas potongan |
| `exclude_already_discounted` | Abaikan item yang sudah diskon |

---

## 7. Katalog Tipe Promo

Berikut jenis promo, deskripsi, parameter, dan contoh konfigurasi. Semua contoh hanya menampilkan blok penting (`scope`, `limits`, dll. mengikuti master schema).

---

### 7.1 Diskon Persentase

**Deskripsi:** Potongan harga dalam persen dari harga item atau subtotal.
**Contoh bisnis:** Diskon 20% semua sepatu.

**Parameter:** `percent`, `apply_to`, `max_amount`, `min_price_floor`

```json
{
  "type": "discount_percent",
  "benefit": {
    "kind": "discount_percent",
    "params": { "percent": 20, "apply_to": "item", "max_amount": 150000 }
  }
}
```

---

### 7.2 Diskon Nominal (Potongan Harga)

**Deskripsi:** Potongan nominal tetap, bisa per item atau per keranjang.
**Contoh bisnis:** Potongan Rp50.000 min. belanja Rp300.000.

**Parameter:** `amount`, `apply_to`, `distribute`, kondisi `cart.eligible_subtotal`

```json
{
  "type": "discount_fixed",
  "conditions": { "all": [{ "fact": "cart.eligible_subtotal", "op": ">=", "value": 300000 }] },
  "benefit": {
    "kind": "discount_fixed",
    "params": { "amount": 50000, "apply_to": "cart", "distribute": "proportional" }
  }
}
```

---

### 7.3 Harga Spesial / Harga Coret (Fixed Price)

**Deskripsi:** Item dijual dengan harga khusus, terlepas dari harga normal.
**Contoh bisnis:** Semua item Rp99.000.

```json
{
  "type": "fixed_price",
  "benefit": { "kind": "fixed_price", "params": { "price": 99000, "per": "item" } }
}
```

---

### 7.4 Buy X Get Y (Termasuk Buy 1 Get 1)

**Deskripsi:** Beli sejumlah X, dapat Y gratis atau diskon. Satu mekanisme dapat membentuk banyak varian.

**Parameter:**

| Parameter | Penjelasan |
|-----------|------------|
| `buy_qty` | Jumlah item yang harus dibeli |
| `get_qty` | Jumlah item bonus |
| `get_discount_percent` | 100 = gratis, 50 = diskon 50% (contoh: *beli 1 diskon 50% item kedua*) |
| `get_item_selection` | `lowest_price`, `highest_price`, `same_sku`, `specific_sku`, `customer_choice` |
| `buy_pool` / `get_pool` | Daftar SKU/kategori untuk bagian "buy" dan "get" (bisa berbeda: beli A dapat B) |
| `repeat` | `true` = kelipatan berlaku |
| `max_repeat` | Batas kelipatan per order |

**Varian dari satu tipe:**

| Varian | Konfigurasi |
|--------|-------------|
| Buy 1 Get 1 Free | `buy_qty=1, get_qty=1, get_discount_percent=100` |
| Buy 2 Get 1 Free | `buy_qty=2, get_qty=1, get_discount_percent=100` |
| Buy 1 Get 1 50% | `buy_qty=1, get_qty=1, get_discount_percent=50` |
| Beli Produk A, Gratis Produk B | `buy_pool=[A], get_pool=[B], get_item_selection=specific_sku` |
| Beli 3 Bayar 2 | `buy_qty=2, get_qty=1, get_discount_percent=100` (setara) |

```json
{
  "type": "buy_x_get_y",
  "benefit": {
    "kind": "buy_x_get_y",
    "params": {
      "buy_qty": 1, "get_qty": 1, "get_discount_percent": 100,
      "get_item_selection": "lowest_price", "repeat": true, "max_repeat": 5
    }
  }
}
```

---

### 7.5 Bundling & Mix and Match

**Deskripsi:** Beberapa item dibeli bersamaan dengan harga paket, atau pelanggan memilih N item dari sebuah pool dengan harga tertentu.

**Parameter:** `bundle_items[]` (SKU + qty), `bundle_price`, atau `pick_qty` + `pool` + `price`

```json
{
  "type": "bundle",
  "benefit": {
    "kind": "bundle_price",
    "params": {
      "mode": "mix_and_match",
      "pool": { "categories": ["CAT-SNACK"] },
      "pick_qty": 3,
      "bundle_price": 50000,
      "repeat": true
    }
  }
}
```

> Contoh lain: *Paket Hemat* (kamera + memory card + tas) harga Rp7.500.000 → `mode: fixed_bundle`.

---

### 7.6 Diskon Bertingkat (Tiered / Volume)

**Deskripsi:** Semakin banyak beli atau semakin besar belanja, semakin besar diskon.

**Parameter:** `tier_basis` (`qty`/`amount`), `mode` (`highest` = hanya tier tertinggi; `cumulative` = bertahap per unit), `tiers[]`

```json
{
  "type": "tiered_discount",
  "benefit": {
    "kind": "tiered_discount",
    "params": {
      "tier_basis": "qty",
      "mode": "highest",
      "tiers": [
        { "min": 2,  "percent": 5 },
        { "min": 5,  "percent": 10 },
        { "min": 10, "percent": 15 }
      ]
    }
  }
}
```

---

### 7.7 Minimum Belanja (Spend & Save / Spend & Get)

**Deskripsi:** Belanja minimal tertentu untuk mendapat diskon, gratis ongkir, atau hadiah.

```json
{
  "type": "spend_and_get",
  "conditions": { "all": [{ "fact": "cart.eligible_subtotal", "op": ">=", "value": 1000000 }] },
  "benefit": { "kind": "discount_percent", "params": { "percent": 10, "apply_to": "cart", "max_amount": 200000 } }
}
```

---

### 7.8 Gratis Ongkir

**Deskripsi:** Subsidi ongkos kirim penuh atau sebagian.

**Parameter:** `max_shipping_subsidy`, `shipping_methods[]`, `regions[]`, `min cart`

```json
{
  "type": "free_shipping",
  "conditions": { "all": [{ "fact": "cart.subtotal", "op": ">=", "value": 150000 }] },
  "benefit": {
    "kind": "free_shipping",
    "params": { "max_shipping_subsidy": 25000, "shipping_methods": ["regular", "same_day"] }
  }
}
```

---

### 7.9 Promo Kartu Kredit / Debit / Bank

**Deskripsi:** Promo yang hanya berlaku jika pembayaran memakai kartu atau bank tertentu. Biasanya dibiayai sebagian oleh bank (lihat bagian Funding).

**Parameter penting:**

| Parameter | Penjelasan |
|-----------|------------|
| `payment.provider` | Bank penerbit |
| `payment.card_bin` | Daftar BIN (`starts_with` / `in`), disimpan sebagai **BIN list** terpisah agar mudah diperbarui |
| `payment.card_type` | Kredit/debit |
| `payment.card_network` | Visa/Mastercard/JCB |
| `min_transaction` | Min. transaksi |
| `max_discount` | Batas potongan |
| `per_card_limit` | Batas per kartu (perlu token/hash kartu) |
| `per_user_limit` | Batas per pengguna |
| `daily_quota` | Kuota harian |

```json
{
  "type": "payment_promo",
  "conditions": {
    "all": [
      { "fact": "payment.method", "op": "==", "value": "credit_card" },
      { "fact": "payment.card_bin", "op": "in_list", "value": "BIN_LIST_BANK_X_CREDIT" },
      { "fact": "cart.subtotal", "op": ">=", "value": 1000000 }
    ]
  },
  "benefit": {
    "kind": "discount_percent",
    "params": { "percent": 15, "apply_to": "cart", "max_amount": 300000 }
  },
  "limits": { "per_user_redemptions": 2, "per_card_redemptions": 1, "daily_quota": 200 },
  "funding": [
    { "party": "bank_x", "share_percent": 60 },
    { "party": "merchant", "share_percent": 40 }
  ]
}
```

**Varian:**
- **Cicilan 0%** → `benefit.kind = installment_subsidy` dengan `tenors: [3, 6, 12]`
- **Cashback kartu** → `benefit.kind = cashback`
- **Promo e-wallet / QRIS** → `payment.method = ewallet/qris`, `payment.provider`
- **Promo PayLater** → `payment.method = paylater`

> **Penting:** diskon promo pembayaran dihitung/dikonfirmasi **setelah metode bayar dipilih**. Jika pelanggan berganti metode, harga harus dihitung ulang.

---

### 7.10 Buyback / Trade-In (Tukar Tambah)

**Deskripsi:** Pelanggan menyerahkan barang lama; nilai taksiran + bonus dipotongkan dari harga barang baru. Umum untuk elektronik, gadget, otomotif, perhiasan.

**Parameter:**

| Parameter | Penjelasan |
|-----------|------------|
| `eligible_old_items` | Kategori/merek/model barang lama yang diterima |
| `credit_source` | `appraisal` (hasil penilaian) atau `fixed` (nilai tetap per model) |
| `condition_multiplier` | Pengali per grade: `{A:1.0, B:0.8, C:0.5, D:0}` |
| `bonus_amount` / `bonus_percent` | Bonus tukar tambah dari merchant/brand |
| `max_credit` | Batas maksimal nilai tukar |
| `min_new_item_price` | Syarat harga barang baru |
| `eligible_new_items` | Barang baru yang boleh dibeli dengan tukar tambah |
| `requires_inspection` | Perlu verifikasi fisik sebelum final |
| `price_lock_days` | Lama harga taksiran terkunci |

```json
{
  "type": "tradein",
  "scope": { "items": { "include": { "categories": ["CAT-SMARTPHONE"] } } },
  "conditions": {
    "all": [
      { "fact": "tradein.device_category", "op": "==", "value": "smartphone" },
      { "fact": "tradein.condition_grade", "op": "in", "value": ["A", "B", "C"] }
    ]
  },
  "benefit": {
    "kind": "tradein_credit",
    "params": {
      "credit_source": "appraisal",
      "condition_multiplier": { "A": 1.0, "B": 0.8, "C": 0.5 },
      "bonus_amount": 500000,
      "max_credit": 8000000,
      "requires_inspection": true,
      "price_lock_days": 7
    }
  }
}
```

**Aturan khusus:**
- Nilai trade-in bersifat **kondisional**: jika inspeksi fisik gagal/grade turun, harga akhir disesuaikan atau transaksi dibatalkan.
- Barang lama masuk alur logistik/inventori terpisah (*reverse logistics*).
- Bedakan antara **buyback** (merchant membeli kembali barang yang dulu dijual, sering dengan harga garansi terhadap penyusutan) dan **trade-in** (nilai dipakai untuk membeli barang baru). Gunakan `params.mode`: `buyback_guarantee` atau `trade_in`.

Contoh **buyback guarantee** (jaminan harga beli kembali):

```json
{
  "type": "buyback_guarantee",
  "benefit": {
    "kind": "tradein_credit",
    "params": {
      "mode": "buyback_guarantee",
      "guarantee_schedule": [
        { "within_months": 12, "percent_of_purchase_price": 60 },
        { "within_months": 24, "percent_of_purchase_price": 40 }
      ],
      "requires_inspection": true
    }
  }
}
```

---

### 7.11 Voucher / Kode Kupon

**Deskripsi:** Promo yang aktif jika pelanggan memasukkan kode atau memiliki voucher di akun.

**Jenis voucher:**

| Jenis | Keterangan |
|-------|------------|
| Generik | Satu kode dipakai banyak orang (mis. `HEMAT10`) |
| Unik | Satu kode satu pengguna (hasil generate massal) |
| Terikat pengguna | Hanya akun tertentu |
| Terbit otomatis | Dikeluarkan oleh promo lain (`voucher_issue`) |

**Parameter:** `code`, `code_pattern` (untuk generate massal), `valid_days_after_issue`, `single_use`, `benefit` (bebas jenis)

```json
{
  "type": "voucher",
  "conditions": { "all": [{ "fact": "context.coupon_code", "op": "==", "value": "HEMAT10" }] },
  "benefit": { "kind": "discount_percent", "params": { "percent": 10, "apply_to": "cart", "max_amount": 50000 } },
  "limits": { "total_redemptions": 5000, "per_user_redemptions": 1 }
}
```

---

### 7.12 Flash Sale

**Deskripsi:** Promo berdurasi singkat dengan stok/kuota terbatas, biasanya harga sangat rendah.

**Parameter:** `schedule` (menit/jam), `stock_per_sku` (stok promo terpisah dari stok total), `per_user_qty`, `reserve_ttl_minutes` (waktu tahan stok di keranjang), `countdown_display`

```json
{
  "type": "flash_sale",
  "schedule": { "start_at": "2026-07-07T12:00:00", "end_at": "2026-07-07T14:00:00", "timezone": "Asia/Jakarta" },
  "benefit": { "kind": "fixed_price", "params": { "price": 199000, "per": "item" } },
  "limits": { "stock_per_sku": 100, "per_user_qty": 1, "reserve_ttl_minutes": 10 }
}
```

---

### 7.13 Gift with Purchase (Hadiah Pembelian)

**Deskripsi:** Barang/hadiah gratis jika syarat terpenuhi. Hadiah bisa ditambahkan otomatis ke keranjang.

**Parameter:** `gift_sku` atau `gift_pool`, `qty`, `auto_add`, `stock_pool` (stok hadiah terbatas), `while_stock_lasts`

```json
{
  "type": "gift_with_purchase",
  "conditions": { "all": [{ "fact": "cart.eligible_subtotal", "op": ">=", "value": 750000 }] },
  "benefit": {
    "kind": "gift",
    "params": { "gift_sku": "GIFT-TOTE-01", "qty": 1, "auto_add": true, "while_stock_lasts": true }
  }
}
```

---

### 7.14 Cashback

**Deskripsi:** Pelanggan membayar penuh, lalu menerima dana kembali (wallet/poin/rekening).

**Parameter:** `percent`/`amount`, `max_amount`, `destination`, `payout_delay_days`, `cancel_on_refund`

```json
{
  "type": "cashback",
  "benefit": {
    "kind": "cashback",
    "params": { "percent": 10, "max_amount": 100000, "destination": "wallet", "payout_delay_days": 7, "cancel_on_refund": true }
  }
}
```

---

### 7.15 Poin Loyalty & Multiplier

**Deskripsi:** Memberi poin ekstra atau pengali poin pada transaksi tertentu.

**Parameter:** `points`, `multiplier`, `max_points`, `expiry_days`

```json
{
  "type": "points_multiplier",
  "benefit": { "kind": "points", "params": { "multiplier": 3, "max_points": 5000, "expiry_days": 365 } }
}
```

---

### 7.16 Promo Pengguna Baru (First Purchase)

**Deskripsi:** Insentif untuk transaksi pertama.

```json
{
  "type": "new_user",
  "conditions": { "all": [{ "fact": "customer.is_new", "op": "==", "value": true }] },
  "benefit": { "kind": "discount_fixed", "params": { "amount": 30000, "apply_to": "cart" } },
  "limits": { "per_user_redemptions": 1 }
}
```

---

### 7.17 Promo Member / Tier / Ulang Tahun

**Deskripsi:** Keuntungan khusus berdasarkan tier atau momen personal.

```json
{
  "type": "member_tier",
  "conditions": {
    "all": [
      { "fact": "customer.tier", "op": "in", "value": ["GOLD", "PLATINUM"] },
      { "fact": "customer.birthday_month", "op": "==", "value": "context.current_month" }
    ]
  },
  "benefit": { "kind": "discount_percent", "params": { "percent": 15, "apply_to": "cart", "max_amount": 150000 } }
}
```

---

### 7.18 Referral (Ajak Teman)

**Deskripsi:** Pengajak dan yang diajak sama-sama mendapat benefit setelah syarat terpenuhi.

**Parameter:** `referrer_benefit`, `referee_benefit`, `qualifying_event` (mis. `first_order_completed`), `min_order_value`, `max_referrals_per_user`, `holding_period_days`

```json
{
  "type": "referral",
  "params": {
    "qualifying_event": "first_order_completed",
    "min_order_value": 100000,
    "referrer_benefit": { "kind": "voucher_issue", "params": { "voucher_template_id": "VCH-REF-REFERRER", "valid_days": 30 } },
    "referee_benefit":  { "kind": "discount_fixed", "params": { "amount": 25000, "apply_to": "cart" } },
    "max_referrals_per_user": 10,
    "holding_period_days": 7
  }
}
```

---

### 7.19 Win-Back / Reaktivasi

**Deskripsi:** Menarik kembali pelanggan yang lama tidak bertransaksi.

```json
{
  "type": "winback",
  "conditions": { "all": [{ "fact": "customer.days_since_last_order", "op": ">=", "value": 90 }] },
  "benefit": { "kind": "discount_percent", "params": { "percent": 12, "apply_to": "cart", "max_amount": 100000 } }
}
```

---

### 7.20 Early Bird / Pre-Order

**Deskripsi:** Harga lebih murah untuk pembeli awal atau pre-order.

```json
{
  "type": "early_bird",
  "conditions": { "all": [{ "fact": "context.now", "op": "<", "value": "2026-08-15T00:00:00" }] },
  "benefit": { "kind": "discount_percent", "params": { "percent": 25, "apply_to": "item" } },
  "limits": { "total_redemptions": 500 }
}
```

---

### 7.21 Ringkasan Tipe Promo

| # | Tipe | Benefit utama | Biasa dipakai untuk |
|---|------|---------------|---------------------|
| 1 | `discount_percent` | Diskon % | Diskon umum, clearance |
| 2 | `discount_fixed` | Potongan Rp | Min. belanja, voucher |
| 3 | `fixed_price` | Harga khusus | Cuci gudang, flash sale |
| 4 | `buy_x_get_y` | Gratis / diskon item | BOGO, beli 3 bayar 2 |
| 5 | `bundle` | Harga paket | Cross-sell, mix & match |
| 6 | `tiered_discount` | Diskon bertingkat | B2B, grosir, naikkan AOV |
| 7 | `spend_and_get` | Diskon/hadiah | Naikkan AOV |
| 8 | `free_shipping` | Subsidi ongkir | Kurangi cart abandonment |
| 9 | `payment_promo` | Diskon/cicilan | Kerja sama bank/e-wallet |
| 10 | `tradein` / `buyback_guarantee` | Kredit tukar | Gadget, otomotif, elektronik |
| 11 | `voucher` | Bebas | Campaign tertarget, CRM |
| 12 | `flash_sale` | Harga khusus + kuota | Urgensi, traffic |
| 13 | `gift_with_purchase` | Barang gratis | Premium value perception |
| 14 | `cashback` | Dana kembali | Dorong penggunaan wallet |
| 15 | `points_multiplier` | Poin | Retensi |
| 16 | `new_user` | Diskon pertama | Akuisisi |
| 17 | `member_tier` | Privilege | Loyalitas |
| 18 | `referral` | Dua sisi | Akuisisi organik |
| 19 | `winback` | Diskon | Reaktivasi |
| 20 | `early_bird` | Diskon awal | Peluncuran produk |

---

## 8. Batasan (Limits & Guardrails)

| Limit | Deskripsi |
|-------|-----------|
| `total_redemptions` | Total pemakaian seluruh pengguna |
| `per_user_redemptions` | Maks. per akun |
| `per_order_redemptions` | Maks. kelipatan per order |
| `per_card_redemptions` | Maks. per kartu (via token/hash) |
| `per_device_redemptions` | Maks. per perangkat |
| `daily_quota` / `hourly_quota` | Kuota periodik |
| `budget_cap` | Total anggaran promo (Rp). Promo otomatis berhenti jika habis |
| `max_discount_per_order` | Batas diskon per order |
| `max_discount_per_item` | Batas diskon per item |
| `min_price_floor` | Harga akhir minimum |
| `min_margin_percent` | Promo tidak berlaku jika margin item di bawah ambang |
| `stock_per_sku` | Stok promo per SKU |
| `min_order_value` / `max_order_value` | Batas nilai order |
| `cooldown_days` | Jeda sebelum pemakaian berikutnya |

**Aturan penting:** semua limit dicek **secara atomik** saat redeem untuk menghindari *race condition* (lihat bagian Edge Case).

---

## 9. Stacking, Prioritas & Konflik

### 9.1 Mode stacking

| Mode | Arti |
|------|------|
| `exclusive` | Jika promo ini berlaku, tidak ada promo lain yang berlaku |
| `exclusive_in_group` | Hanya satu promo per `group` yang berlaku |
| `stackable` | Boleh digabung dengan promo lain |
| `best_of` | Dari beberapa kandidat satu group, pilih yang paling menguntungkan pelanggan |

### 9.2 Grup promo yang disarankan

| Group | Contoh isi |
|-------|-----------|
| `item_discount` | Diskon item, BOGO, fixed price, tiered |
| `cart_discount` | Spend & save, voucher |
| `shipping` | Gratis ongkir |
| `payment` | Promo kartu/bank/e-wallet |
| `reward` | Cashback, poin |
| `gift` | Gift with purchase |
| `tradein` | Trade-in/buyback |

### 9.3 Matriks gabungan default (dapat diubah via konfigurasi)

| | item_discount | cart_discount | shipping | payment | reward | gift | tradein |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **item_discount** | ✗ (pilih 1) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **cart_discount** | ✓ | ✗ (pilih 1) | ✓ | ✓ | ✓ | ✓ | ✓ |
| **shipping** | ✓ | ✓ | ✗ (pilih 1) | ✓ | ✓ | ✓ | ✓ |
| **payment** | ✓ | ✓ | ✓ | ✗ (pilih 1) | ✓ | ✓ | ✓ |
| **reward** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **gift** | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ (pilih 1) | ✓ |
| **tradein** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ (pilih 1) |

> Matriks ini disimpan sebagai **tabel konfigurasi**, bukan kode, agar bisa diubah tanpa deployment.

### 9.4 Resolusi konflik (urutan)

1. Promo `exclusive` dengan `priority` tertinggi menang.
2. Dalam satu `group`: gunakan `best_of` (nilai benefit terbesar bagi pelanggan) atau `priority` tertinggi.
3. Jika nilai sama: promo dengan `end_at` paling dekat menang; jika masih sama, `id` terkecil (agar deterministik).
4. Setiap promo yang tidak berlaku mencatat **alasan** (mis. `LOSES_TO_HIGHER_PRIORITY`, `MIN_SPEND_NOT_MET`) untuk ditampilkan/di-debug.

---

## 10. Urutan Kalkulasi (Pricing Pipeline)

Urutan baku agar hasil konsisten:

```
1. Harga dasar item (base price / list price)
2. Promo level item        → item_discount (BOGO, fixed price, tiered, flash sale)
3. Subtotal setelah promo item
4. Promo level keranjang   → cart_discount (spend & save, voucher)
5. Trade-in credit         → nilai tukar dikurangkan
6. Ongkos kirim            → free_shipping / subsidi
7. Promo pembayaran        → diskon kartu/e-wallet (setelah metode bayar dipilih)
8. Pajak (PPN)             → sesuai kebijakan: harga inklusif/eksklusif pajak
9. Grand total
10. Reward pasca-transaksi → cashback, poin, voucher issue (tidak mengurangi total)
```

**Aturan kalkulasi:**
- Semua uang disimpan sebagai **integer satuan terkecil** (mis. rupiah, atau sen untuk mata uang desimal) untuk menghindari kesalahan floating point.
- **Distribusi diskon keranjang ke item** secara proporsional (penting untuk retur dan laporan pajak). Sisa pembulatan diberikan ke item bernilai terbesar.
- Pembulatan mengikuti parameter `rounding` + `rounding_unit`.
- Pajak: definisikan konfigurasi `tax_mode` (`inclusive`/`exclusive`) dan apakah diskon mengurangi dasar pengenaan pajak.
- Harga akhir item tidak boleh negatif dan tidak boleh di bawah `min_price_floor`.

---

## 11. Pendanaan Promo (Funding)

Pelacakan "siapa menanggung biaya" penting untuk rekonsiliasi dengan bank, brand/principal, dan laporan finansial.

| Pihak | Contoh |
|-------|--------|
| `merchant` | Penjual/retailer |
| `brand` / `principal` | Pemilik merek |
| `bank_x` / `payment_partner` | Bank, e-wallet, issuer |
| `platform` | Marketplace/aplikasi |

```json
"funding": [
  { "party": "bank_x",   "share_percent": 50, "cap_amount": 100000000 },
  { "party": "merchant", "share_percent": 50 }
]
```

**Aturan:**
- Total `share_percent` = 100.
- Setiap redemption menyimpan **snapshot pembagian biaya** (nominal per pihak) agar laporan tidak berubah jika konfigurasi diedit.
- Jika `cap_amount` pihak ketiga habis, sisanya otomatis dialihkan sesuai kebijakan (`fallback: merchant` atau `stop_promo`).

---

## 12. Lifecycle & Approval

```
draft → pending_approval → scheduled → active ⇄ paused → expired
                 │                         │
                 └──────→ rejected         └──────→ cancelled
```

| Status | Keterangan |
|--------|------------|
| `draft` | Sedang disusun, belum berlaku |
| `pending_approval` | Menunggu persetujuan (mis. margin rendah, budget besar) |
| `scheduled` | Disetujui, menunggu `start_at` |
| `active` | Berlaku |
| `paused` | Dihentikan sementara (manual atau otomatis karena guardrail) |
| `expired` | Lewat `end_at` atau budget/kuota habis |
| `cancelled` | Dibatalkan |

**Aturan approval (configurable):**
- Budget di atas ambang → perlu persetujuan finance.
- Diskon di atas X% atau margin di bawah Y% → perlu persetujuan manajer.
- Promo pembayaran → perlu konfirmasi kesepakatan dengan mitra.
- Semua perubahan dicatat dalam **audit log** (siapa, kapan, sebelum/sesudah).

**Fitur operasional:**
- **Dry-run / simulator:** uji promo terhadap keranjang contoh dan histori transaksi.
- **Clone promo:** duplikasi untuk campaign serupa.
- **Kill switch:** matikan promo atau seluruh engine secara instan.
- **Template promo:** preset tipe promo agar marketing tinggal mengisi parameter.

---

## 13. Desain Database

### 13.1 Tabel inti

```
promotions
  id, code, name, description, type, status, priority, version,
  config_json (JSON: scope, conditions, benefit, limits, stacking, funding, display),
  start_at, end_at, timezone,
  created_by, approved_by, created_at, updated_at

promotion_versions
  id, promotion_id, version, config_json, changed_by, changed_at, change_reason

promotion_schedules              -- jadwal berulang (opsional jika tidak di JSON)
  id, promotion_id, day_of_week, time_from, time_to

promotion_scope_items            -- hasil pra-hitung scope untuk performa
  id, promotion_id, ref_type (sku/category/brand/tag), ref_value, is_exclude

promotion_budgets
  promotion_id, budget_cap, budget_used, redemption_cap, redemption_used, updated_at

vouchers
  id, promotion_id, code, status, owner_customer_id, valid_from, valid_to, redeemed_at

bin_lists
  list_id, name, description
bin_list_entries
  list_id, bin_prefix, bank, card_type, card_network, valid_from, valid_to

fact_registry
  fact_key, data_type, source, description, is_active

stacking_rules
  group_a, group_b, can_stack (bool)

redemptions
  id, promotion_id, promotion_version, order_id, customer_id,
  discount_amount, benefit_snapshot_json, funding_snapshot_json,
  status (reserved/confirmed/reversed), idempotency_key, created_at

redemption_counters              -- untuk limit per user/kartu/perangkat
  promotion_id, subject_type, subject_key, count, last_redeemed_at

tradein_requests
  id, order_id, customer_id, device_json, claimed_grade, appraised_value,
  inspected_grade, final_value, status, price_lock_until

audit_logs
  id, entity_type, entity_id, action, actor, before_json, after_json, created_at
```

### 13.2 Catatan desain
- `config_json` fleksibel (JSON/JSONB) → tipe promo baru tidak butuh migrasi skema.
- Validasi `config_json` memakai **JSON Schema per tipe promo** (disimpan di `promo_type_schemas`), sehingga input marketing divalidasi sebelum disimpan.
- Index penting: `(status, start_at, end_at)`, `(promotion_id, customer_id)`, `(subject_type, subject_key)`, `code` untuk voucher.
- Gunakan cache (mis. Redis) untuk promo aktif dan counter kuota *hot*, dengan sumber kebenaran di database.

---

## 14. Desain API

| Endpoint | Fungsi |
|----------|--------|
| `POST /v1/promos/evaluate` | Hitung promo untuk keranjang (tanpa menyimpan, aman dipanggil berulang) |
| `POST /v1/promos/reserve` | Cadangkan kuota/voucher saat checkout dimulai (TTL) |
| `POST /v1/promos/redeem` | Konfirmasi pemakaian setelah pembayaran berhasil (idempoten) |
| `POST /v1/promos/rollback` | Batalkan/kembalikan promo (cancel/refund) |
| `GET /v1/promos/applicable` | Daftar promo yang tersedia untuk pelanggan/produk (untuk tampilan di UI) |
| `GET/POST/PUT /v1/admin/promos` | CRUD promo (dashboard) |
| `POST /v1/admin/promos/{id}/simulate` | Dry-run terhadap data contoh |
| `POST /v1/admin/promos/{id}/transition` | Ubah status (approve, pause, cancel) |

**Contoh request `evaluate`:**

```json
{
  "customer": { "id": "C123", "tier": "GOLD", "is_new": false },
  "context": { "channel": "app", "store_id": "ONLINE", "now": "2026-06-15T10:00:00+07:00", "coupon_code": "HEMAT10" },
  "cart": {
    "items": [
      { "sku": "SKU-001", "qty": 2, "unit_price": 150000, "category": "CAT-TSHIRT", "brand": "BRAND-A" }
    ],
    "shipping_fee": 20000
  },
  "payment": { "method": "credit_card", "card_bin": "412345", "installment_tenor": 0 },
  "tradein": null
}
```

**Contoh response:**

```json
{
  "applied": [
    { "promo_id": "promo_001", "name": "Beli 1 Gratis 1", "group": "item_discount", "discount": 150000, "target": "item:SKU-001" },
    { "promo_id": "promo_045", "name": "Gratis Ongkir", "group": "shipping", "discount": 20000, "target": "shipping" }
  ],
  "rejected": [
    { "promo_id": "promo_020", "reason": "LOSES_TO_HIGHER_PRIORITY" },
    { "promo_id": "promo_033", "reason": "MIN_SPEND_NOT_MET", "detail": { "required": 1000000, "actual": 300000 } }
  ],
  "totals": { "subtotal": 300000, "discount_total": 170000, "shipping": 0, "grand_total": 130000 },
  "rewards": [{ "kind": "points", "value": 130 }]
}
```

**Prinsip API:**
- `evaluate` bersifat **read-only** dan sering dipanggil (cepat, cacheable).
- `reserve` → `redeem` memisahkan pencadangan dan konfirmasi agar kuota tidak bocor.
- Semua endpoint penulisan memakai **idempotency key**.

---

## 15. Edge Case Penting

| Kasus | Penanganan yang disarankan |
|-------|----------------------------|
| **Race condition kuota** | Decrement atomik (transaksi DB / atomic counter) saat `reserve`; hindari baca-lalu-tulis |
| **Reservasi tidak dikonfirmasi** | Reserve punya TTL; job pembersih mengembalikan kuota |
| **Retur sebagian (partial return)** | Hitung ulang diskon proporsional; BOGO: jika item "buy" dikembalikan, diskon item "get" dibatalkan atau nilainya ditagihkan kembali |
| **Pembatalan order** | `rollback` mengembalikan kuota, voucher, poin, dan membatalkan cashback pending |
| **Perubahan metode bayar** | Hitung ulang promo pembayaran saat metode berubah |
| **Pergantian harga saat promo** | Gunakan harga saat transaksi; simpan snapshot harga & versi promo |
| **Item sudah diskon** | Parameter `exclude_already_discounted` |
| **Stok promo habis di tengah checkout** | Beri tahu pelanggan, hitung ulang tanpa promo atau tawarkan alternatif |
| **Pembulatan** | Pakai integer satuan terkecil; sisa pembulatan ke item terbesar |
| **Zona waktu & DST** | Simpan semua waktu dalam UTC + timezone promo; evaluasi di timezone promo |
| **Promo lintas tengah malam** | Jadwal berulang mendukung window yang melewati 00:00 |
| **Diskon > harga item** | Terapkan `min_price_floor` (default 0) |
| **Voucher dipakai bersamaan** | Penguncian baris / unique constraint pada `(voucher_id, order_id)` |
| **Trade-in gagal inspeksi** | Status `needs_reprice`; pelanggan boleh lanjut dengan nilai baru atau batal |
| **Mata uang berbeda** | Simpan `currency` di promo & order; konversi hanya lewat kurs terdokumentasi |
| **Perubahan promo saat aktif** | Buat versi baru; order yang sedang berjalan tetap memakai versi lama sampai selesai |
| **Promo untuk bundle yang sebagian tersedia** | Definisikan `allow_partial_bundle` (default false) |

---

## 16. Anti-Fraud & Abuse

| Risiko | Mitigasi |
|--------|----------|
| Akun palsu untuk promo pengguna baru | Verifikasi nomor HP/email, device fingerprint, limit per perangkat/alamat |
| Penyalahgunaan voucher massal | Kode unik, rate limiting, deteksi pola |
| Satu kartu banyak akun | Token/hash kartu, `per_card_redemptions` |
| Referral palsu (self-referral) | Deteksi device/IP/alamat sama, `holding_period_days`, wajib transaksi riil |
| Beli lalu retur untuk ambil benefit | Cashback/poin dibayarkan setelah masa retur; clawback saat retur |
| Reseller memborong flash sale | `per_user_qty`, verifikasi tambahan, limit alamat pengiriman |
| Stacking tak terduga | Matriks stacking eksplisit + `max_discount_per_order` global |
| Manipulasi nilai trade-in | Wajib inspeksi fisik, verifikasi IMEI/serial, blacklist perangkat |
| Insider abuse | Role-based access, approval, audit log |

**Guardrail global (konfigurasi sistem):**
- `global_max_discount_percent_per_order`
- `global_min_margin_percent`
- `global_daily_budget_alert`
- Alert otomatis jika redemption rate melonjak abnormal.

---

## 17. Analitik & KPI

**Event yang dicatat:** `promo_viewed`, `promo_eligible`, `promo_applied`, `promo_rejected(reason)`, `promo_reserved`, `promo_redeemed`, `promo_reversed`.

| KPI | Rumus / Arti |
|-----|--------------|
| **Redemption rate** | Redeem ÷ eligible/viewed |
| **Incremental revenue** | Pendapatan dibanding grup kontrol/baseline |
| **Promo ROI** | (Incremental gross profit − biaya promo) ÷ biaya promo |
| **AOV uplift** | Perubahan rata-rata nilai order |
| **Conversion uplift** | Perubahan konversi dibanding baseline |
| **Cannibalization rate** | Penjualan yang sebenarnya akan terjadi tanpa promo |
| **Cost per redemption** | Biaya promo ÷ jumlah redemption |
| **Budget burn rate** | Budget terpakai per hari vs rencana |
| **New customer share** | Persentase pelanggan baru dari redemption |
| **Repeat rate pasca promo** | Pelanggan promo yang kembali beli (tanpa promo) |
| **Margin impact** | Margin sebelum vs sesudah promo |
| **Return rate promo** | Retur pada order promo |

**Praktik:** gunakan **holdout group** (sebagian pelanggan tidak ditampilkan promo) untuk mengukur dampak sebenarnya, bukan hanya jumlah redemption.

---

## 18. Checklist Testing

**Unit test (per tipe promo)**
- [ ] Hitungan benar untuk skenario normal
- [ ] Batas bawah/atas (qty = 0, 1, tepat di ambang, melebihi `max_repeat`)
- [ ] Pembulatan & distribusi diskon
- [ ] Kondisi `all/any/not` kombinasi
- [ ] Item tereksklusi tidak ikut terhitung

**Integrasi**
- [ ] Stacking sesuai matriks
- [ ] Prioritas & tie-breaker deterministik
- [ ] `reserve → redeem → rollback` konsisten
- [ ] Idempotensi (request ganda tidak menggandakan efek)
- [ ] Perubahan metode bayar menghitung ulang

**Konkurensi & performa**
- [ ] 1.000 request bersamaan pada kuota 100 → tepat 100 yang berhasil
- [ ] Latensi `evaluate` sesuai target (mis. p95 < 200 ms)

**Bisnis/UAT**
- [ ] Marketing dapat membuat tiap tipe promo dari dashboard tanpa developer
- [ ] Simulasi dengan data historis menghasilkan angka yang masuk akal
- [ ] Laporan funding cocok dengan perhitungan finance
- [ ] Retur/refund menghitung ulang dengan benar

---

## 19. Panduan Marketing: Memilih Mekanisme Promo

| Tujuan bisnis | Mekanisme yang cocok | Catatan |
|---------------|----------------------|---------|
| Akuisisi pelanggan baru | New user, referral, voucher pertama | Pastikan anti-fraud kuat |
| Naikkan AOV | Spend & get, tiered, bundle, gratis ongkir dengan minimum | Set ambang ±15–30% di atas AOV saat ini |
| Habiskan stok / clearance | Diskon %, BOGO, fixed price | Cek margin dan risiko cannibalization |
| Premium value perception | Gift with purchase, trade-in bonus | Hindari menurunkan harga produk utama |
| Retensi & loyalitas | Poin multiplier, tier privilege, birthday | Fokus nilai jangka panjang |
| Reaktivasi | Win-back, voucher personal | Segmentasi berdasarkan recency |
| Kerja sama bank/e-wallet | Promo kartu, cicilan 0%, cashback | Biaya dibagi lewat funding |
| Urgensi & traffic | Flash sale, early bird | Kuota terbatas, siapkan kapasitas server |
| Penjualan produk high-ticket | Trade-in, buyback guarantee, cicilan 0% | Kurangi hambatan harga awal |
| Kurangi cart abandonment | Gratis ongkir, voucher terbatas waktu | Uji A/B |

**Prinsip praktis yang umum dipakai secara global:**
1. **Promo harus punya tujuan terukur** (mis. +10% AOV, bukan sekadar "ramai").
2. **Hitung break-even** sebelum meluncurkan: kenaikan volume yang dibutuhkan agar promo tetap menguntungkan.
3. **Hindari "promo terus-menerus"**: pelanggan terbiasa menunggu diskon dan merusak persepsi harga.
4. **Pakai cap dan kuota** untuk melindungi margin.
5. **Sederhana lebih baik**: syarat yang terlalu rumit menurunkan konversi dan memicu komplain.
6. **Uji dengan A/B atau holdout** sebelum scale.
7. **Selaraskan dengan inventori & operasional**: promo laku tapi stok/CS/logistik tidak siap merusak pengalaman.
8. **Pertimbangkan aspek hukum/regulasi**: transparansi harga, syarat & ketentuan jelas, aturan perlindungan konsumen, dan aturan promosi kartu/keuangan setempat (konfirmasi dengan tim legal).

---

## 20. Roadmap Implementasi

| Fase | Cakupan | Hasil |
|------|---------|-------|
| **Fase 1 (MVP)** | Master schema, diskon %/nominal, voucher, min. belanja, gratis ongkir, limit dasar, evaluate/redeem | Promo dasar berjalan tanpa hardcode |
| **Fase 2** | Buy X Get Y, bundle, tiered, flash sale, stacking & prioritas, dry-run | Promo ritel kompleks |
| **Fase 3** | Promo pembayaran (BIN list, cicilan), funding & rekonsiliasi, approval workflow | Kerja sama bank/partner |
| **Fase 4** | Trade-in/buyback, reverse logistics, inspeksi | Promo high-ticket |
| **Fase 5** | Loyalty, referral, win-back, personalisasi, analitik ROI, holdout testing | Optimasi berbasis data |
| **Berkelanjutan** | Fact registry baru, tipe benefit baru, anti-fraud tuning | Skalabilitas |

---

## 21. Glosarium

| Istilah | Arti |
|---------|------|
| **AOV** | Average Order Value, rata-rata nilai pesanan |
| **BIN** | Bank Identification Number, 6-8 digit pertama kartu |
| **BOGO** | Buy One Get One |
| **Buyback** | Pembelian kembali barang oleh penjual, kadang dengan harga yang dijamin |
| **Trade-in** | Tukar tambah: nilai barang lama dipakai untuk membeli barang baru |
| **Cannibalization** | Promo menarik pembeli yang sebenarnya akan beli tanpa promo |
| **Dry-run** | Simulasi tanpa dampak nyata |
| **Funding** | Pembagian siapa yang menanggung biaya promo |
| **Holdout group** | Kelompok kontrol yang tidak mendapat promo |
| **Idempotent** | Operasi yang aman diulang tanpa efek ganda |
| **Redemption** | Pemakaian/klaim promo |
| **Stacking** | Penggabungan beberapa promo dalam satu transaksi |
| **Fact** | Data yang dapat dievaluasi dalam kondisi promo (mis. `cart.subtotal`) |
| **GWP** | Gift With Purchase |
| **Clawback** | Penarikan kembali benefit yang sudah diberikan (mis. saat retur) |

---

## Lampiran A. Template Promo Kosong

```json
{
  "id": "",
  "code": "",
  "name": "",
  "description": "",
  "type": "",
  "status": "draft",
  "priority": 0,
  "version": 1,
  "schedule": { "start_at": "", "end_at": "", "timezone": "Asia/Jakarta", "recurrence": null },
  "scope": {
    "channels": ["web", "app", "pos"],
    "stores": { "include": ["ALL"], "exclude": [] },
    "items": { "include": { "categories": [], "brands": [], "skus": [], "tags": [] }, "exclude": { "categories": [], "brands": [], "skus": [], "tags": [] } }
  },
  "conditions": { "all": [] },
  "benefit": { "kind": "", "params": {} },
  "limits": {
    "total_redemptions": null,
    "per_user_redemptions": null,
    "per_order_redemptions": null,
    "budget_cap": null,
    "max_discount_per_order": null,
    "min_margin_percent": null
  },
  "stacking": { "mode": "exclusive_in_group", "group": "", "can_combine_with": [], "cannot_combine_with": [] },
  "funding": [{ "party": "merchant", "share_percent": 100 }],
  "display": { "badge": "", "banner_url": "", "short_text": "", "terms_and_conditions": "" },
  "metadata": { "created_by": "", "approved_by": "", "campaign_id": "", "tags": [] }
}
```

## Lampiran B. Pertanyaan yang Perlu Dijawab Sebelum Implementasi

1. Channel apa saja yang akan memakai engine ini (web, app, POS, marketplace)?
2. Apakah harga inklusif atau eksklusif pajak? Bagaimana diskon memengaruhi pajak?
3. Mata uang tunggal atau multi-currency?
4. Siapa yang berwenang membuat, menyetujui, dan menghentikan promo?
5. Apakah ada integrasi dengan bank/e-wallet (BIN list, settlement)?
6. Bagaimana kebijakan retur terhadap promo (BOGO, cashback, poin)?
7. Apakah promo perlu personalisasi per pelanggan (segmen CRM)?
8. Apakah ada kebutuhan promo offline di POS dengan koneksi tidak stabil (mode offline)?
9. Target volume (request per detik) saat puncak (flash sale, harbolnas)?
10. Sistem apa yang menjadi sumber data produk, stok, harga, dan pelanggan?
