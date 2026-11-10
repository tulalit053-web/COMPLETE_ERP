import React from "react";
import {
  CurrencyCode,
  formatDateShort,
  formatMoney,
  LangCode,
  ReturnEventItem,
  tr,
} from "@/lib/promo-types";
import { ReturnSimInput, ReturnSimOutput } from "./returns.service";
import styles from "./Returns.module.css";

interface ReturnsViewProps {
  lang: LangCode;
  currency: CurrencyCode;
  rate: number;
  returnEvents: ReturnEventItem[];
  onOpenPromo: (promoCode: string) => void;
  simInput: ReturnSimInput;
  onSimInputChange: (next: ReturnSimInput) => void;
  onSimulateReturn: (mode: "evaluate" | "commit") => void;
  simOutput: ReturnSimOutput | null;
  loadingSim: boolean;
}

export default function ReturnsView({
  lang,
  currency,
  rate,
  returnEvents,
  onOpenPromo,
  simInput,
  onSimInputChange,
  onSimulateReturn,
  simOutput,
  loadingSim,
}: ReturnsViewProps) {
  return (
    <div className={styles.container}>
      {/* Return Events Table */}
      <div className={styles.card}>
        <div className={styles.cardHead}>
          <div className={styles.cardTitle}>{tr("ev", lang)}</div>
          <div className={styles.cardSub}>
            PRORATE · RECALCULATE · CLAWBACK · RETAIN
          </div>
        </div>

        <div className={styles.tableWrap}>
          <table className={styles.table}>
            <thead>
              <tr>
                <th>ID</th>
                <th>{tr("ord", lang)}</th>
                <th>{tr("name", lang)}</th>
                <th>{tr("act", lang)}</th>
                <th>{tr("refund", lang)}</th>
              </tr>
            </thead>
            <tbody>
              {returnEvents.map((r) => (
                <tr
                  key={r.returnNo}
                  className={styles.rowClick}
                  onClick={() => onOpenPromo(r.promoId)}
                >
                  <td className={styles.mono}>{r.returnNo}</td>
                  <td>
                    <span className={styles.mono}>{r.orderId}</span>
                    <div style={{ color: "#6b7280", fontSize: 11.5 }}>
                      {formatDateShort(r.returnedAt, lang)}
                    </div>
                  </td>
                  <td>
                    <span className={styles.tag}>{r.promoId}</span>
                  </td>
                  <td>{r.actionText?.[lang] || r.actionText?.id}</td>
                  <td>
                    <strong>
                      {formatMoney(r.netRefund, currency, lang, rate)}
                    </strong>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Interactive Return Calculator */}
      <div className={styles.card}>
        <div className={styles.cardHead}>
          <div>
            <div className={styles.cardTitle}>
              Kalkulator &amp; Eksekusi Kebijakan Retur (/v1/returns/evaluate)
            </div>
            <div className={styles.cardSub}>
              Uji perhitungan clawback / prorate diskon atau simpan peristiwa retur baru.
            </div>
          </div>
        </div>

        <div className={styles.simGrid}>
          <div className={styles.field}>
            <label>Order ID</label>
            <input
              value={simInput.orderId}
              onChange={(e) =>
                onSimInputChange({ ...simInput, orderId: e.target.value })
              }
            />
          </div>
          <div className={styles.field}>
            <label>Kode Promo</label>
            <select
              value={simInput.promoId}
              onChange={(e) =>
                onSimInputChange({ ...simInput, promoId: e.target.value })
              }
            >
              <option value="P-101">P-101 (Beli 2 Gratis 1 - CLAWBACK)</option>
              <option value="P-102">P-102 (Flash Sale - PRORATE)</option>
              <option value="P-103">P-103 (Kartu BCA - RECALCULATE)</option>
              <option value="P-108">P-108 (Tiered - RECALCULATE)</option>
            </select>
          </div>
          <div className={styles.field}>
            <label>Alasan Retur</label>
            <select
              value={simInput.reasonCode}
              onChange={(e) =>
                onSimInputChange({
                  ...simInput,
                  reasonCode: e.target.value as ReturnSimInput["reasonCode"],
                })
              }
            >
              <option value="CUSTOMER_REMORSE">
                CUSTOMER_REMORSE (Berubah Pikiran)
              </option>
              <option value="DEFECT">
                DEFECT (Barang Cacat - Fault Override RETAIN)
              </option>
              <option value="MERCHANT_FAULT">
                MERCHANT_FAULT (Salah Kirim - RETAIN)
              </option>
            </select>
          </div>
          <div className={styles.field}>
            <label>Tipe Retur</label>
            <select
              value={simInput.returnType}
              onChange={(e) =>
                onSimInputChange({
                  ...simInput,
                  returnType: e.target.value as ReturnSimInput["returnType"],
                })
              }
            >
              <option value="PARTIAL">PARTIAL (Retur Sebagian)</option>
              <option value="FULL">FULL (Retur Semua)</option>
              <option value="EXCHANGE">EXCHANGE (Tukar Barang Setara)</option>
            </select>
          </div>
          <div className={styles.field}>
            <label>Harga Barang Diretur (IDR)</label>
            <input
              type="number"
              value={simInput.unitPrice}
              onChange={(e) =>
                onSimInputChange({
                  ...simInput,
                  unitPrice: Number(e.target.value),
                })
              }
            />
          </div>
          <div className={styles.field}>
            <label>Diskon yang Diterima (IDR)</label>
            <input
              type="number"
              value={simInput.allocatedDiscount}
              onChange={(e) =>
                onSimInputChange({
                  ...simInput,
                  allocatedDiscount: Number(e.target.value),
                })
              }
            />
          </div>
        </div>

        <div style={{ display: "flex", gap: 8 }}>
          <button
            type="button"
            className={`${styles.btn} ${styles.btnPri}`}
            onClick={() => onSimulateReturn("evaluate")}
            disabled={loadingSim}
          >
            Hitung Preview Refund
          </button>
          <button
            type="button"
            className={styles.btn}
            onClick={() => onSimulateReturn("commit")}
            disabled={loadingSim}
          >
            Commit &amp; Simpan Peristiwa Retur
          </button>
        </div>

        {simOutput && (
          <div className={styles.resultBox}>
            <div style={{ fontWeight: 600, marginBottom: 4 }}>
              Kebijakan Diterapkan: {simOutput.policyApplied}
            </div>
            <div style={{ color: "#6b7280", marginBottom: 8 }}>
              {simOutput.explanation}
            </div>
            <div style={{ display: "flex", gap: 20, flexWrap: "wrap" }}>
              <span>
                Gross:{" "}
                <strong>
                  {formatMoney(simOutput.grossRefund, currency, lang, rate)}
                </strong>
              </span>
              <span style={{ color: "#dc2626" }}>
                Clawback / Potongan Diskon:{" "}
                <strong>
                  -{" "}
                  {formatMoney(
                    simOutput.discountClawback,
                    currency,
                    lang,
                    rate
                  )}
                </strong>
              </span>
              <span style={{ color: "#059669" }}>
                Net Refund Diterima Pelanggan:{" "}
                <strong>
                  {formatMoney(simOutput.netRefund, currency, lang, rate)}
                </strong>
              </span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
