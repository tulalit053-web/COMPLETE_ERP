import React from "react";
import {
  CurrencyCode,
  formatDateShort,
  formatMoney,
  LangCode,
  PromoItem,
  tr,
  UserRole,
} from "@/lib/promo-types";
import styles from "./Approvals.module.css";

interface ApprovalsViewProps {
  lang: LangCode;
  currency: CurrencyCode;
  role: UserRole;
  rate: number;
  pendingPromos: PromoItem[];
  onSelectPromo: (promo: PromoItem) => void;
  onApprove: (promo: PromoItem) => void;
  onReject: (promo: PromoItem) => void;
}

export default function ApprovalsView({
  lang,
  currency,
  role,
  rate,
  pendingPromos,
  onSelectPromo,
  onApprove,
  onReject,
}: ApprovalsViewProps) {
  if (pendingPromos.length === 0) {
    return (
      <div className={styles.card} style={{ color: "#6b7280" }}>
        {tr("nA", lang)}
      </div>
    );
  }

  return (
    <div className={styles.list}>
      {pendingPromos.map((p) => {
        const title = p.localizedNames?.[lang] || p.name;
        const cfg = (p.config || {}) as Record<string, unknown>;
        const summaryObj = (cfg.summary as Record<string, string>) || {};

        return (
          <div key={p.code} className={styles.card}>
            <div className={styles.row}>
              <div>
                <div
                  style={{
                    display: "flex",
                    gap: 8,
                    alignItems: "center",
                    marginBottom: 4,
                  }}
                >
                  <span className={styles.mono}>
                    {p.code} · v{p.version}
                  </span>
                  <span className={styles.tag}>{tr(p.type, lang)}</span>
                </div>
                <div style={{ fontWeight: 600, fontSize: 15 }}>{title}</div>
                <div
                  style={{
                    color: "#6b7280",
                    fontSize: 12.5,
                    marginTop: 4,
                  }}
                >
                  {summaryObj[lang] || p.description || title}
                </div>
                <div
                  style={{
                    fontSize: 12,
                    color: "#6b7280",
                    marginTop: 8,
                  }}
                >
                  {tr("mk", lang)}:{" "}
                  <strong style={{ color: "#111827" }}>{p.makerId}</strong> ·{" "}
                  {tr("budget", lang)}:{" "}
                  <strong style={{ color: "#111827" }}>
                    {formatMoney(p.budgetCap, currency, lang, rate)}
                  </strong>{" "}
                  · {tr("exp", lang)}:{" "}
                  <strong style={{ color: "#111827" }}>
                    {formatDateShort(p.expiresAt, lang)}
                  </strong>
                </div>
              </div>

              <div className={styles.actions}>
                <button
                  className={styles.btn}
                  onClick={() => onSelectPromo(p)}
                >
                  Detail
                </button>
                {role === "checker" ? (
                  <>
                    <button
                      className={`${styles.btn} ${styles.btnOk}`}
                      onClick={() => onApprove(p)}
                    >
                      {tr("approve", lang)}
                    </button>
                    <button
                      className={`${styles.btn} ${styles.btnBad}`}
                      onClick={() => onReject(p)}
                    >
                      {tr("reject", lang)}
                    </button>
                  </>
                ) : (
                  <span style={{ fontSize: 12, color: "#6b7280" }}>
                    {tr("mkNote", lang)}
                  </span>
                )}
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
