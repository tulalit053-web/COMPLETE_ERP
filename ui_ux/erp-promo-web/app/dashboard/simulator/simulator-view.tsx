import React from "react";
import {
  CurrencyCode,
  formatMoney,
  LangCode,
} from "@/lib/promo-types";
import {
  SimulatorEvaluatePayload,
  SimulatorEvaluateResult,
} from "./simulator.service";
import styles from "./Simulator.module.css";

interface SimulatorViewProps {
  lang: LangCode;
  currency: CurrencyCode;
  rate: number;
  payload: SimulatorEvaluatePayload;
  onPayloadChange: (next: SimulatorEvaluatePayload) => void;
  onApplyPreset: (presetName: "bxgy" | "bca" | "newuser" | "tiered") => void;
  onRunSimulation: () => void;
  running: boolean;
  result: SimulatorEvaluateResult | null;
}

export default function SimulatorView({
  lang,
  currency,
  rate,
  payload,
  onPayloadChange,
  onApplyPreset,
  onRunSimulation,
  running,
  result,
}: SimulatorViewProps) {
  const firstLine = payload.cart.lines[0] || {
    lineId: "L1",
    sku: "SKU-TEE-01",
    category: "APPAREL",
    brand: "ERP",
    qty: 2,
    unitPrice: 150000,
  };

  return (
    <div className={styles.grid}>
      {/* Left: Cart & Context Input */}
      <div className={styles.card}>
        <div>
          <div className={styles.cardTitle}>
            {lang === "id"
              ? "Simulasi Keranjang & Rule Engine (/v1/promos/evaluate)"
              : "Cart & Rule Engine Simulator (/v1/promos/evaluate)"}
          </div>
          <div style={{ fontSize: 12, color: "#6b7280", marginTop: 2 }}>
            {lang === "id"
              ? "Pilih skenario preset atau ubah parameter keranjang untuk menguji evaluasi promo real-time."
              : "Pick a preset scenario or tweak cart parameters to test real-time promo evaluation."}
          </div>
        </div>

        <div className={styles.presets}>
          <button
            type="button"
            className={styles.presetBtn}
            onClick={() => onApplyPreset("bxgy")}
          >
            Skenario 1: Beli 2 Gratis 1 Kaos (P-101)
          </button>
          <button
            type="button"
            className={styles.presetBtn}
            onClick={() => onApplyPreset("bca")}
          >
            Skenario 2: Kartu Kredit BCA Rp600rb (P-103)
          </button>
          <button
            type="button"
            className={styles.presetBtn}
            onClick={() => onApplyPreset("tiered")}
          >
            Skenario 3: Belanja Rp1,2 Juta Tiered (P-108)
          </button>
          <button
            type="button"
            className={styles.presetBtn}
            onClick={() => onApplyPreset("newuser")}
          >
            Skenario 4: Pengguna Baru + Voucher WELCOME50
          </button>
        </div>

        <div className={styles.fieldGrid}>
          <div className={styles.field}>
            <label>Channel</label>
            <select
              value={payload.channel}
              onChange={(e) =>
                onPayloadChange({ ...payload, channel: e.target.value })
              }
            >
              <option value="APP">Mobile App (APP)</option>
              <option value="WEB">Website (WEB)</option>
              <option value="POS">Toko Fisik (POS)</option>
            </select>
          </div>
          <div className={styles.field}>
            <label>Tier Pelanggan</label>
            <select
              value={payload.customer.tier}
              onChange={(e) =>
                onPayloadChange({
                  ...payload,
                  customer: { ...payload.customer, tier: e.target.value },
                })
              }
            >
              <option value="GOLD">GOLD</option>
              <option value="SILVER">SILVER</option>
              <option value="PLATINUM">PLATINUM</option>
            </select>
          </div>
        </div>

        <div className={styles.fieldGrid}>
          <div className={styles.field}>
            <label>SKU Produk</label>
            <input
              value={firstLine.sku}
              onChange={(e) =>
                onPayloadChange({
                  ...payload,
                  cart: {
                    ...payload.cart,
                    lines: [{ ...firstLine, sku: e.target.value }],
                  },
                })
              }
            />
          </div>
          <div className={styles.field}>
            <label>Kategori</label>
            <input
              value={firstLine.category}
              onChange={(e) =>
                onPayloadChange({
                  ...payload,
                  cart: {
                    ...payload.cart,
                    lines: [{ ...firstLine, category: e.target.value }],
                  },
                })
              }
            />
          </div>
        </div>

        <div className={styles.fieldGrid}>
          <div className={styles.field}>
            <label>Qty Barang</label>
            <input
              type="number"
              min={1}
              value={firstLine.qty}
              onChange={(e) =>
                onPayloadChange({
                  ...payload,
                  cart: {
                    ...payload.cart,
                    lines: [
                      { ...firstLine, qty: Math.max(1, Number(e.target.value)) },
                    ],
                  },
                })
              }
            />
          </div>
          <div className={styles.field}>
            <label>Harga Satuan (IDR)</label>
            <input
              type="number"
              min={0}
              value={firstLine.unitPrice}
              onChange={(e) =>
                onPayloadChange({
                  ...payload,
                  cart: {
                    ...payload.cart,
                    lines: [
                      { ...firstLine, unitPrice: Number(e.target.value) },
                    ],
                  },
                })
              }
            />
          </div>
        </div>

        <div className={styles.fieldGrid}>
          <div className={styles.field}>
            <label>Ongkos Kirim (IDR)</label>
            <input
              type="number"
              min={0}
              value={payload.cart.shippingFee}
              onChange={(e) =>
                onPayloadChange({
                  ...payload,
                  cart: {
                    ...payload.cart,
                    shippingFee: Number(e.target.value),
                  },
                })
              }
            />
          </div>
          <div className={styles.field}>
            <label>Kode Voucher (opsional)</label>
            <input
              value={payload.cart.vouchers[0] || ""}
              placeholder="Mis. WELCOME50"
              onChange={(e) =>
                onPayloadChange({
                  ...payload,
                  cart: {
                    ...payload.cart,
                    vouchers: e.target.value.trim()
                      ? [e.target.value.trim()]
                      : [],
                  },
                })
              }
            />
          </div>
        </div>

        <div className={styles.fieldGrid}>
          <div className={styles.field}>
            <label>Metode Pembayaran</label>
            <select
              value={payload.payment.method}
              onChange={(e) =>
                onPayloadChange({
                  ...payload,
                  payment: { ...payload.payment, method: e.target.value },
                })
              }
            >
              <option value="CARD">Kartu Kredit / Debit (CARD)</option>
              <option value="VA">Virtual Account (VA)</option>
              <option value="QRIS">QRIS</option>
            </select>
          </div>
          <div className={styles.field}>
            <label>BIN Kartu (6 digit)</label>
            <input
              value={payload.payment.bin}
              placeholder="411111 (BCA)"
              onChange={(e) =>
                onPayloadChange({
                  ...payload,
                  payment: { ...payload.payment, bin: e.target.value },
                })
              }
            />
          </div>
        </div>

        <button
          type="button"
          className={styles.runBtn}
          onClick={onRunSimulation}
          disabled={running}
        >
          {running
            ? "Mengevaluasi Rule Engine..."
            : "Jalankan Evaluasi Promo Sekarang →"}
        </button>
      </div>

      {/* Right: Evaluation Output */}
      <div className={styles.card}>
        <div className={styles.cardTitle}>
          {lang === "id"
            ? "Hasil Evaluasi & Alokasi Diskon"
            : "Evaluation Result & Discount Allocation"}
        </div>

        {!result ? (
          <div style={{ color: "#6b7280" }}>
            Klik tombol evaluasi untuk melihat hasil perhitungan engine.
          </div>
        ) : (
          <>
            <div className={styles.summaryBox}>
              <div className={styles.sumRow}>
                <span>Subtotal Barang</span>
                <strong>
                  {formatMoney(result.subtotal, currency, lang, rate)}
                </strong>
              </div>
              <div className={styles.sumRow}>
                <span>Ongkos Kirim</span>
                <strong>
                  {formatMoney(result.shippingFee, currency, lang, rate)}
                </strong>
              </div>
              <div className={styles.sumRow} style={{ color: "#059669" }}>
                <span>Total Diskon Barang</span>
                <strong>
                  - {formatMoney(result.totalDiscount, currency, lang, rate)}
                </strong>
              </div>
              <div className={styles.sumRow} style={{ color: "#059669" }}>
                <span>Diskon Ongkir</span>
                <strong>
                  - {formatMoney(result.shippingDiscount, currency, lang, rate)}
                </strong>
              </div>
              <div className={styles.sumGrand}>
                <span>Grand Total Bayar</span>
                <span style={{ color: "#4f46e5" }}>
                  {formatMoney(result.grandTotal, currency, lang, rate)}
                </span>
              </div>
            </div>

            <div>
              <div
                style={{
                  fontSize: 12,
                  fontWeight: 600,
                  color: "#059669",
                  marginBottom: 6,
                }}
              >
                Promo Diterapkan ({result.appliedPromos.length})
              </div>
              <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                {result.appliedPromos.length === 0 ? (
                  <div style={{ fontSize: 12.5, color: "#6b7280" }}>
                    Tidak ada promo yang memenuhi syarat.
                  </div>
                ) : (
                  result.appliedPromos.map((ap) => (
                    <div key={ap.code} className={styles.appliedCard}>
                      <div>
                        <strong>
                          {ap.code} · {ap.name}
                        </strong>
                        <div style={{ fontSize: 11.5, color: "#047857" }}>
                          Benefit: {ap.benefitKind} · Retur:{" "}
                          {ap.returnPolicyMode}
                        </div>
                      </div>
                      <strong style={{ color: "#059669" }}>
                        - {formatMoney(ap.discountAmount, currency, lang, rate)}
                      </strong>
                    </div>
                  ))
                )}
              </div>
            </div>

            <div>
              <div
                style={{
                  fontSize: 12,
                  fontWeight: 600,
                  color: "#dc2626",
                  marginBottom: 6,
                }}
              >
                Promo Ditolak / Tidak Berlaku ({result.rejectedPromos.length})
              </div>
              <div
                style={{
                  display: "flex",
                  flexDirection: "column",
                  gap: 6,
                  maxHeight: 220,
                  overflowY: "auto",
                }}
              >
                {result.rejectedPromos.map((rp, idx) => (
                  <div key={`${rp.code}-${idx}`} className={styles.rejectedCard}>
                    <span className={styles.mono}>
                      <strong>{rp.code}</strong> ({rp.reasonCode})
                    </span>
                    <span>{rp.message}</span>
                  </div>
                ))}
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
