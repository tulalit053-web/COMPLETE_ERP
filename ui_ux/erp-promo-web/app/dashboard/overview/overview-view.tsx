import React from "react";
import {
  CurrencyCode,
  DashboardOverviewData,
  formatMoney,
  LangCode,
  PromoItem,
  tr,
} from "@/lib/promo-types";
import { StatusMixCounts } from "./overview.service";
import styles from "./Overview.module.css";

interface OverviewViewProps {
  lang: LangCode;
  currency: CurrencyCode;
  data: DashboardOverviewData;
  statusMix: StatusMixCounts;
  burnPromos: PromoItem[];
  topRoiPromos: PromoItem[];
  onSelectPromo: (promo: PromoItem) => void;
  onNavigateApprovals: () => void;
}

function Sparkline({ points, color }: { points: number[]; color: string }) {
  const max = Math.max(...points);
  const min = Math.min(...points);
  const d = points
    .map((v, i) => {
      const x = (i / (points.length - 1)) * 58 + 1;
      const y = 18 - ((v - min) / (max - min || 1)) * 14;
      return `${i ? "L" : "M"}${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");
  return (
    <svg width={60} height={20}>
      <path d={d} fill="none" stroke={color} strokeWidth={1.6} strokeLinecap="round" />
    </svg>
  );
}

function TrendChart({ series }: { series: number[] }) {
  const pts = series.length > 1 ? series : [420, 510, 480, 620, 790, 910, 1080];
  const w = 560;
  const h = 150;
  const p = 18;
  const max = Math.max(...pts) * 1.1;
  const coords = pts.map((v, i) => [
    p + (i / (pts.length - 1)) * (w - p * 2),
    h - p - (v / (max || 1)) * (h - p * 2),
  ]);
  const line = coords
    .map((c, i) => `${i ? "L" : "M"}${c[0].toFixed(1)},${c[1].toFixed(1)}`)
    .join(" ");
  const area = `${line} L${coords[coords.length - 1][0]},${h - p} L${coords[0][0]},${
    h - p
  } Z`;

  return (
    <svg viewBox={`0 0 ${w} ${h}`} style={{ width: "100%", height: 150 }}>
      <defs>
        <linearGradient id="trendGrad" x1="0" x2="0" y1="0" y2="1">
          <stop offset="0%" stopColor="#4f46e5" stopOpacity={0.18} />
          <stop offset="100%" stopColor="#4f46e5" stopOpacity={0} />
        </linearGradient>
      </defs>
      <line x1={p} y1={h - p} x2={w - p} y2={h - p} stroke="#eef0f4" />
      <line x1={p} y1={h / 2} x2={w - p} y2={h / 2} stroke="#eef0f4" strokeDasharray="3 3" />
      <path d={area} fill="url(#trendGrad)" />
      <path d={line} fill="none" stroke="#4f46e5" strokeWidth={2} />
      {coords.map((c, idx) => (
        <circle key={idx} cx={c[0]} cy={c[1]} r={2.5} fill="#4f46e5" />
      ))}
    </svg>
  );
}

export default function OverviewView({
  lang,
  currency,
  data,
  statusMix,
  burnPromos,
  topRoiPromos,
  onSelectPromo,
  onNavigateApprovals,
}: OverviewViewProps) {
  const rate = data.fxRateUsdIdr || 16000;
  const totalPromos = data.promotions.length || 1;
  const colors: Record<keyof StatusMixCounts, string> = {
    active: "#059669",
    scheduled: "#2563eb",
    pending: "#d97706",
    paused: "#9ca3af",
    expired: "#dc2626",
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
      {/* 6 KPI Cards */}
      <div className={styles.kpis}>
        <div className={styles.kpi}>
          <div className={styles.kLabel}>{tr("kAct", lang)}</div>
          <div className={styles.kVal}>{data.kpi.activePromos}</div>
          <div className={styles.kSub}>
            <span className={styles.up}>+2 mgg ini</span>
            <Sparkline points={[3, 4, 4, 5, 4, 5, 5]} color="#059669" />
          </div>
        </div>

        <div className={styles.kpi}>
          <div className={styles.kLabel}>{tr("kBud", lang)}</div>
          <div className={styles.kVal}>{data.kpi.budgetUsedPercent}%</div>
          <div className={styles.kSub}>
            <span>
              {formatMoney(data.kpi.totalBudgetUsed, currency, lang, rate, true)} /{" "}
              {formatMoney(data.kpi.totalBudgetCap, currency, lang, rate, true)}
            </span>
          </div>
        </div>

        <div className={styles.kpi}>
          <div className={styles.kLabel}>{tr("kRed", lang)}</div>
          <div className={styles.kVal}>{data.kpi.totalRedemptions.toLocaleString()}</div>
          <div className={styles.kSub}>
            <span className={styles.up}>+14.2%</span>
            <Sparkline points={[6, 7, 8, 7, 9, 11, 12]} color="#4f46e5" />
          </div>
        </div>

        <div className={styles.kpi}>
          <div className={styles.kLabel}>{tr("kDis", lang)}</div>
          <div className={styles.kVal}>
            {formatMoney(data.kpi.totalBudgetUsed, currency, lang, rate, true)}
          </div>
          <div className={styles.kSub}>
            <span>ROI rata-rata 4.5x</span>
          </div>
        </div>

        <div className={styles.kpi}>
          <div className={styles.kLabel}>{tr("kPen", lang)}</div>
          <div className={styles.kVal}>{data.kpi.pendingApprovals}</div>
          <div className={styles.kSub}>
            <span className={styles.warn}>SLA &lt; 24j</span>
          </div>
        </div>

        <div className={styles.kpi}>
          <div className={styles.kLabel}>{tr("kExp", lang)}</div>
          <div className={styles.kVal}>{data.kpi.expiringWithin7Days}</div>
          <div className={styles.kSub}>
            <span className={styles.warn}>P-102, P-106</span>
          </div>
        </div>
      </div>

      {/* Row 2: Redemption Trend + Status Mix */}
      <div className={styles.grid2}>
        <div className={styles.card}>
          <div className={styles.cardHead}>
            <div>
              <div className={styles.cardTitle}>{tr("trend", lang)}</div>
              <div className={styles.cardSub}>5–18 Apr 2026 · semua channel</div>
            </div>
            <div style={{ fontWeight: 600, color: "#059669", fontSize: 12.5 }}>
              ▲ 1.480 hari ini
            </div>
          </div>
          <TrendChart series={data.trend14d} />
        </div>

        <div className={styles.card}>
          <div className={styles.cardHead}>
            <div className={styles.cardTitle}>{tr("mix", lang)}</div>
            <div className={styles.cardSub}>{data.promotions.length} total</div>
          </div>
          <div className={styles.mixBar}>
            {(Object.keys(statusMix) as Array<keyof StatusMixCounts>).map((k) => (
              <div
                key={k}
                style={{
                  width: `${(statusMix[k] / totalPromos) * 100}%`,
                  background: colors[k],
                }}
              />
            ))}
          </div>
          <div className={styles.legend}>
            {(Object.keys(statusMix) as Array<keyof StatusMixCounts>).map((k) => (
              <div key={k} className={styles.legItem}>
                <span className={styles.legLeft}>
                  <span className={styles.sw} style={{ background: colors[k] }} />
                  {tr(k, lang)}
                </span>
                <strong>{statusMix[k]}</strong>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Row 3: Budget Burn + Needs Attention + Top Promos ROI */}
      <div className={styles.grid3}>
        <div className={styles.card}>
          <div className={styles.cardHead}>
            <div className={styles.cardTitle}>{tr("burn", lang)}</div>
          </div>
          <div>
            {burnPromos.map((p) => {
              const pct = Math.round((p.budgetUsed / (p.budgetCap || 1)) * 100);
              const fillCls =
                pct >= 95
                  ? styles.barFillBad
                  : pct >= 80
                  ? styles.barFillWarn
                  : "";
              const title = p.localizedNames?.[lang] || p.name;
              return (
                <div
                  key={p.code}
                  className={styles.barRow}
                  onClick={() => onSelectPromo(p)}
                >
                  <div className={styles.barHead}>
                    <span>{title}</span>
                    <span style={{ color: "#6b7280" }}>{pct}%</span>
                  </div>
                  <div className={styles.barTrack}>
                    <div
                      className={`${styles.barFill} ${fillCls}`}
                      style={{ width: `${Math.min(100, pct)}%` }}
                    />
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        <div className={styles.card}>
          <div className={styles.cardHead}>
            <div className={styles.cardTitle}>{tr("alerts", lang)}</div>
          </div>
          <div className={styles.list}>
            <div
              className={styles.alert}
              onClick={() => {
                const p = data.promotions.find((x) => x.code === "P-102");
                if (p) onSelectPromo(p);
              }}
            >
              <span className={styles.aDot} style={{ background: "#d97706" }} />
              <div>
                <strong>P-102</strong> · {tr("aBud", lang)} (89%) &amp;{" "}
                {tr("aExp", lang)} 3 {tr("d", lang)}
              </div>
            </div>

            <div className={styles.alert} onClick={onNavigateApprovals}>
              <span className={styles.aDot} style={{ background: "#4f46e5" }} />
              <div>
                <strong>P-107</strong> · {tr("aPen", lang)} (Ayu → checker)
              </div>
            </div>

            <div
              className={styles.alert}
              onClick={() => {
                const p = data.promotions.find((x) => x.code === "P-106");
                if (p) onSelectPromo(p);
              }}
            >
              <span className={styles.aDot} style={{ background: "#dc2626" }} />
              <div>
                <strong>P-106</strong> · Budget 100% — auto-jeda aktif
              </div>
            </div>

            <div className={styles.alert} style={{ cursor: "default" }}>
              <span className={styles.aDot} style={{ background: "#059669" }} />
              <div>{tr("aFx", lang)}</div>
            </div>
          </div>
        </div>

        <div className={styles.card}>
          <div className={styles.cardHead}>
            <div className={styles.cardTitle}>{tr("top", lang)}</div>
          </div>
          <div className={styles.list}>
            {topRoiPromos.map((p) => {
              const title = p.localizedNames?.[lang] || p.name;
              return (
                <div
                  key={p.code}
                  className={styles.alert}
                  onClick={() => onSelectPromo(p)}
                >
                  <div
                    style={{
                      display: "flex",
                      justifyContent: "space-between",
                      width: "100%",
                      alignItems: "center",
                    }}
                  >
                    <div>
                      <strong>{title}</strong>
                      <div style={{ color: "#6b7280", fontSize: 11.5 }}>
                        {p.redemptionUsed.toLocaleString()}× · RR {p.returnRate}%
                      </div>
                    </div>
                    <strong style={{ color: "#059669" }}>{p.roi}x</strong>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
