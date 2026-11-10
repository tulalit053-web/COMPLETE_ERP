import React from "react";
import {
  CurrencyCode,
  formatDateShort,
  formatMoney,
  LangCode,
  PromoItem,
  PromoStatus,
  tr,
} from "@/lib/promo-types";
import { CreatePromoFormInput } from "./promos.service";
import styles from "./Promos.module.css";

interface PromosViewProps {
  lang: LangCode;
  currency: CurrencyCode;
  rate: number;
  statusFilter: PromoStatus;
  onStatusFilterChange: (s: PromoStatus) => void;
  totalCount: number;
  filteredPromos: PromoItem[];
  onSelectPromo: (promo: PromoItem) => void;
  canAddPromo: boolean;
  showCreateModal: boolean;
  onOpenCreateModal: () => void;
  onCloseCreateModal: () => void;
  formInput: CreatePromoFormInput;
  onFormChange: (next: CreatePromoFormInput) => void;
  onSubmitCreate: (e: React.FormEvent) => void;
  creating: boolean;
}

const STATUS_TABS: PromoStatus[] = [
  "all",
  "active",
  "scheduled",
  "pending",
  "paused",
  "expired",
];

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

export default function PromosView({
  lang,
  currency,
  rate,
  statusFilter,
  onStatusFilterChange,
  totalCount,
  filteredPromos,
  onSelectPromo,
  canAddPromo,
  showCreateModal,
  onOpenCreateModal,
  onCloseCreateModal,
  formInput,
  onFormChange,
  onSubmitCreate,
  creating,
}: PromosViewProps) {
  return (
    <div className={styles.card}>
      <div className={styles.cardHead}>
        <div className={styles.chips}>
          {STATUS_TABS.map((s) => (
            <button
              key={s}
              className={`${styles.chip} ${
                statusFilter === s ? styles.chipOn : ""
              }`}
              onClick={() => onStatusFilterChange(s)}
            >
              {tr(s, lang)}
            </button>
          ))}
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <span style={{ color: "#6b7280", fontSize: 12 }}>
            {filteredPromos.length} / {totalCount}
          </span>
          {canAddPromo && (
            <button className={styles.newBtn} onClick={onOpenCreateModal}>
              {tr("newPromo", lang)}
            </button>
          )}
        </div>
      </div>

      <div className={styles.tableWrap}>
        <table className={styles.table}>
          <thead>
            <tr>
              <th>{tr("name", lang)}</th>
              <th>{tr("type", lang)}</th>
              <th>{tr("status", lang)}</th>
              <th>{tr("period", lang)}</th>
              <th>{tr("exp", lang)}</th>
              <th>{tr("budget", lang)}</th>
              <th>{tr("red", lang)}</th>
            </tr>
          </thead>
          <tbody>
            {filteredPromos.length === 0 ? (
              <tr>
                <td colSpan={7} style={{ color: "#6b7280" }}>
                  {tr("none", lang)}
                </td>
              </tr>
            ) : (
              filteredPromos.map((p) => {
                const pct = Math.round(
                  (p.budgetUsed / (p.budgetCap || 1)) * 100
                );
                const dLeft = p.daysUntilExpiry;
                const expColor =
                  dLeft < 0
                    ? "#dc2626"
                    : dLeft <= 7
                    ? "#d97706"
                    : "#6b7280";
                const expLabel =
                  dLeft < 0
                    ? `${Math.abs(dLeft)}h lalu`
                    : `${dLeft} ${tr("d", lang)}`;
                const title = p.localizedNames?.[lang] || p.name;

                return (
                  <tr
                    key={p.code}
                    className={styles.rowClick}
                    onClick={() => onSelectPromo(p)}
                  >
                    <td>
                      <div style={{ fontWeight: 600 }}>{title}</div>
                      <div className={styles.mono} style={{ color: "#6b7280" }}>
                        {p.code} · v{p.version} · {p.companyCode || `COMP0${p.companyId || 1}`}
                      </div>
                    </td>
                    <td>
                      <span className={styles.tag}>{tr(p.type, lang)}</span>
                    </td>
                    <td>
                      <span
                        className={`${styles.pill} ${getStatusPillClass(
                          p.status
                        )}`}
                      >
                        <span className={styles.dot} />
                        {tr(p.status, lang)}
                      </span>
                    </td>
                    <td style={{ color: "#6b7280" }}>
                      {formatDateShort(p.startAt, lang)} –{" "}
                      {formatDateShort(p.endAt, lang)}
                    </td>
                    <td>
                      <div style={{ fontWeight: 500 }}>
                        {formatDateShort(p.expiresAt, lang)}
                      </div>
                      <div style={{ fontSize: 11.5, color: expColor }}>
                        {expLabel}
                      </div>
                    </td>
                    <td style={{ minWidth: 160 }}>
                      <div
                        style={{
                          display: "flex",
                          justifyContent: "space-between",
                          fontSize: 12,
                          marginBottom: 4,
                        }}
                      >
                        <span>
                          {formatMoney(p.budgetUsed, currency, lang, rate, true)}
                        </span>
                        <span style={{ color: "#6b7280" }}>{pct}%</span>
                      </div>
                      <div className={styles.barTrack}>
                        <div
                          className={`${styles.barFill} ${
                            pct >= 95
                              ? styles.barBad
                              : pct >= 80
                              ? styles.barWarn
                              : ""
                          }`}
                          style={{ width: `${Math.min(100, pct)}%` }}
                        />
                      </div>
                    </td>
                    <td>
                      <div>{p.redemptionUsed.toLocaleString()}</div>
                      <div style={{ fontSize: 11.5, color: "#6b7280" }}>
                        / {p.redemptionCap.toLocaleString()}
                      </div>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      {showCreateModal && (
        <div
          className={styles.modalBg}
          onClick={(e) => {
            if (e.target === e.currentTarget) onCloseCreateModal();
          }}
        >
          <form className={styles.modal} onSubmit={onSubmitCreate}>
            <div style={{ fontWeight: 600, fontSize: 15 }}>
              Buat Promo Baru (Config-Driven v1.1)
            </div>

            <div className={styles.formGrid}>
              <div className={styles.field}>
                <label>Kode Promo</label>
                <input
                  required
                  value={formInput.code}
                  onChange={(e) =>
                    onFormChange({ ...formInput, code: e.target.value })
                  }
                />
              </div>
              <div className={styles.field}>
                <label>Tipe Promo</label>
                <select
                  value={formInput.promoTypeCode}
                  onChange={(e) =>
                    onFormChange({ ...formInput, promoTypeCode: e.target.value })
                  }
                >
                  <option value="flash_sale">Flash Sale</option>
                  <option value="buy_x_get_y">Beli X Gratis Y</option>
                  <option value="free_shipping">Gratis Ongkir</option>
                  <option value="payment_promo">Promo Kartu</option>
                  <option value="tiered_discount">Diskon Bertingkat</option>
                </select>
              </div>
            </div>

            <div className={styles.field}>
              <label>Nama Promo</label>
              <input
                required
                value={formInput.name}
                onChange={(e) =>
                  onFormChange({ ...formInput, name: e.target.value })
                }
                placeholder="Mis. Promo Gajian Akhir Bulan 20%"
              />
            </div>

            <div className={styles.formGrid}>
              <div className={styles.field}>
                <label>Mulai (Start Date)</label>
                <input
                  type="date"
                  required
                  value={formInput.startAt}
                  onChange={(e) =>
                    onFormChange({ ...formInput, startAt: e.target.value })
                  }
                />
              </div>
              <div className={styles.field}>
                <label>Expired Date (Wajib)</label>
                <input
                  type="date"
                  required
                  value={formInput.expiresAt}
                  onChange={(e) =>
                    onFormChange({
                      ...formInput,
                      endAt: e.target.value,
                      expiresAt: e.target.value,
                    })
                  }
                />
              </div>
            </div>

            <div className={styles.formGrid}>
              <div className={styles.field}>
                <label>Jenis Benefit</label>
                <select
                  value={formInput.benefitKind}
                  onChange={(e) =>
                    onFormChange({
                      ...formInput,
                      benefitKind: e.target.value as
                        | "PERCENT"
                        | "FIXED_AMOUNT"
                        | "FREE_SHIPPING",
                    })
                  }
                >
                  <option value="PERCENT">Diskon Persentase (%)</option>
                  <option value="FIXED_AMOUNT">Potongan Nominal (Rp)</option>
                  <option value="FREE_SHIPPING">Gratis Ongkir (Rp)</option>
                </select>
              </div>
              <div className={styles.field}>
                <label>Nilai Benefit (% atau Rp)</label>
                <input
                  type="number"
                  required
                  value={formInput.benefitValue}
                  onChange={(e) =>
                    onFormChange({
                      ...formInput,
                      benefitValue: Number(e.target.value),
                    })
                  }
                />
              </div>
            </div>

            <div className={styles.formGrid}>
              <div className={styles.field}>
                <label>Budget Cap (IDR)</label>
                <input
                  type="number"
                  required
                  value={formInput.budgetCap}
                  onChange={(e) =>
                    onFormChange({
                      ...formInput,
                      budgetCap: Number(e.target.value),
                    })
                  }
                />
              </div>
              <div className={styles.field}>
                <label>Kuota Redemption</label>
                <input
                  type="number"
                  required
                  value={formInput.redemptionCap}
                  onChange={(e) =>
                    onFormChange({
                      ...formInput,
                      redemptionCap: Number(e.target.value),
                    })
                  }
                />
              </div>
            </div>

            <div
              style={{
                display: "flex",
                justifyContent: "flex-end",
                gap: 8,
                marginTop: 6,
              }}
            >
              <button
                type="button"
                className={styles.chip}
                onClick={onCloseCreateModal}
              >
                {tr("cancel", lang)}
              </button>
              <button
                type="submit"
                className={styles.newBtn}
                disabled={creating}
              >
                {creating ? "Menyimpan..." : tr("ok", lang)}
              </button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
}
