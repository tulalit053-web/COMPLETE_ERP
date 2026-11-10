import React from "react";
import { formatDateShort, LangCode, tr } from "@/lib/promo-types";
import { UnifiedAuditEntry } from "./audit.service";
import styles from "./Audit.module.css";

interface AuditViewProps {
  lang: LangCode;
  entries: UnifiedAuditEntry[];
  onOpenPromo: (promoCode: string) => void;
}

export default function AuditView({
  lang,
  entries,
  onOpenPromo,
}: AuditViewProps) {
  return (
    <div className={styles.card}>
      <div className={styles.cardHead}>
        <div className={styles.cardTitle}>{tr("aud", lang)}</div>
        <div className={styles.cardSub}>Append-only · before/after snapshot</div>
      </div>

      <div className={styles.tl}>
        {entries.map((it, idx) => (
          <div
            key={`${it.promoCode}-${idx}`}
            className={styles.tlItem}
            onClick={() => onOpenPromo(it.promoCode)}
          >
            <div>
              <strong>{it.actor}</strong> {tr(it.action, lang)}{" "}
              <span className={styles.tag}>{it.promoCode}</span>{" "}
              {it.promoName[lang]} ·{" "}
              <span style={{ color: "#6b7280" }}>
                {formatDateShort(it.date, lang)}
              </span>
            </div>
            {it.note && <div style={{ color: "#6b7280" }}>{it.note}</div>}
          </div>
        ))}
      </div>
    </div>
  );
}
