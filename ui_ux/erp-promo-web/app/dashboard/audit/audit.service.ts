import { AuditLogItem, PromoItem } from "@/lib/promo-types";

export interface UnifiedAuditEntry {
  date: string;
  actor: string;
  action: string;
  note?: string;
  promoCode: string;
  promoName: { id: string; en: string };
}

export function buildUnifiedAuditTimeline(
  promotions: PromoItem[],
  auditLogs: AuditLogItem[]
): UnifiedAuditEntry[] {
  const entries: UnifiedAuditEntry[] = [];

  for (const p of promotions) {
    const pName = p.localizedNames || { id: p.name, en: p.name };
    for (const h of p.history || []) {
      entries.push({
        date: h.date,
        actor: h.actor,
        action: h.action.toLowerCase(),
        note: h.note,
        promoCode: p.code,
        promoName: pName,
      });
    }
  }

  if (entries.length === 0) {
    for (const log of auditLogs) {
      entries.push({
        date: log.createdAt,
        actor: log.actor,
        action: log.action.toLowerCase(),
        note: log.reason,
        promoCode: log.entityId,
        promoName: { id: log.entityId, en: log.entityId },
      });
    }
  }

  return entries.sort((a, b) => b.date.localeCompare(a.date));
}
