package com.erp.system.service;

import com.erp.system.dto.PromoAdminDto;
import com.erp.system.entity.*;
import com.erp.system.repository.*;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.stream.Collectors;

@Service
public class DashboardReferenceService {

    private final PromoAdminGovernanceService promoAdminService;
    private final TenantRbacService tenantRbacService;
    private final PrmTxnReturnEventRepository returnEventRepository;
    private final PrmTxnReturnAdjustmentRepository returnAdjustmentRepository;
    private final PrmLogAuditRepository auditRepository;
    private final PrmMstCurrencyRepository currencyRepository;
    private final PrmMstLocaleRepository localeRepository;
    private final PrmMstChannelRepository channelRepository;
    private final PrmMstPromoTypeRepository promoTypeRepository;
    private final PrmMstFactRepository factRepository;
    private final PrmMstBenefitKindRepository benefitKindRepository;
    private final PrmMstStackingRuleRepository stackingRuleRepository;
    private final PrmMstApprovalMatrixRepository approvalMatrixRepository;
    private final PrmMstFxRateRepository fxRateRepository;

    public DashboardReferenceService(
            PromoAdminGovernanceService promoAdminService,
            TenantRbacService tenantRbacService,
            PrmTxnReturnEventRepository returnEventRepository,
            PrmTxnReturnAdjustmentRepository returnAdjustmentRepository,
            PrmLogAuditRepository auditRepository,
            PrmMstCurrencyRepository currencyRepository,
            PrmMstLocaleRepository localeRepository,
            PrmMstChannelRepository channelRepository,
            PrmMstPromoTypeRepository promoTypeRepository,
            PrmMstFactRepository factRepository,
            PrmMstBenefitKindRepository benefitKindRepository,
            PrmMstStackingRuleRepository stackingRuleRepository,
            PrmMstApprovalMatrixRepository approvalMatrixRepository,
            PrmMstFxRateRepository fxRateRepository) {
        this.promoAdminService = promoAdminService;
        this.tenantRbacService = tenantRbacService;
        this.returnEventRepository = returnEventRepository;
        this.returnAdjustmentRepository = returnAdjustmentRepository;
        this.auditRepository = auditRepository;
        this.currencyRepository = currencyRepository;
        this.localeRepository = localeRepository;
        this.channelRepository = channelRepository;
        this.promoTypeRepository = promoTypeRepository;
        this.factRepository = factRepository;
        this.benefitKindRepository = benefitKindRepository;
        this.stackingRuleRepository = stackingRuleRepository;
        this.approvalMatrixRepository = approvalMatrixRepository;
        this.fxRateRepository = fxRateRepository;
    }

    public Map<String, Object> getDashboardOverview() {
        return getDashboardOverview(null, null);
    }

    public Map<String, Object> getDashboardOverview(String requestedUsername, Integer requestedCompanyId) {
        Map<String, Object> userContext = tenantRbacService.getUserContext(requestedUsername, requestedCompanyId);
        Integer effectiveCompanyId = (Integer) userContext.get("effectiveCompanyId");

        List<PromoAdminDto> promos = promoAdminService.listPromotionsByCompany(effectiveCompanyId);
        Set<String> allowedPromoIds = promos.stream()
                .map(PromoAdminDto::getId)
                .collect(Collectors.toSet());
        Set<String> allowedPromoCodes = promos.stream()
                .map(PromoAdminDto::getCode)
                .collect(Collectors.toSet());

        long activeCount = promos.stream().filter(p -> "active".equals(p.getStatus())).count();
        long pendingCount = promos.stream().filter(p -> "pending".equals(p.getStatus())).count();
        long expiringSoonCount = promos.stream()
                .filter(p -> List.of("active", "scheduled", "paused").contains(p.getStatus())
                        && p.getDaysUntilExpiry() != null
                        && p.getDaysUntilExpiry() >= 0 && p.getDaysUntilExpiry() <= 7)
                .count();

        long totalBudgetCap = promos.stream().mapToLong(p -> Optional.ofNullable(p.getBudgetCap()).orElse(0L)).sum();
        long totalBudgetUsed = promos.stream().mapToLong(p -> Optional.ofNullable(p.getBudgetUsed()).orElse(0L)).sum();
        int totalRedemptions = promos.stream().mapToInt(p -> Optional.ofNullable(p.getRedemptionUsed()).orElse(0)).sum();
        int budgetUsedPct = totalBudgetCap > 0 ? (int) Math.round((totalBudgetUsed * 100.0) / totalBudgetCap) : 0;

        List<Map<String, Object>> returnEvents = getReturnEventsSummary(effectiveCompanyId, allowedPromoIds, allowedPromoCodes);
        List<PrmLogAudit> audits = auditRepository.findTop100ByOrderByCreatedAtDesc().stream()
                .filter(a -> effectiveCompanyId == null
                        || effectiveCompanyId.equals(a.getCompanyId())
                        || allowedPromoIds.contains(a.getEntityId())
                        || allowedPromoCodes.contains(a.getEntityId()))
                .collect(Collectors.toList());

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("userContext", userContext);
        res.put("kpi", Map.of(
                "activePromos", activeCount,
                "budgetUsedPercent", budgetUsedPct,
                "totalBudgetCap", totalBudgetCap,
                "totalBudgetUsed", totalBudgetUsed,
                "totalRedemptions", totalRedemptions,
                "pendingApprovals", pendingCount,
                "expiringWithin7Days", expiringSoonCount
        ));
        res.put("trend14d", List.of(210, 260, 240, 310, 380, 350, 420, 460, 430, 520, 560, 540, 610, 680));
        res.put("promotions", promos);
        res.put("returnEvents", returnEvents);
        res.put("auditLogs", audits);
        res.put("fxRateUsdIdr", fxRateRepository.findFirstByBaseCurrencyAndQuoteCurrencyOrderByEffectiveAtDesc("USD", "IDR")
                .map(PrmMstFxRate::getRate).orElse(new java.math.BigDecimal("16000")));
        return res;
    }

    public List<Map<String, Object>> getReturnEventsSummary(
            Integer effectiveCompanyId,
            Set<String> allowedPromoIds,
            Set<String> allowedPromoCodes) {
        List<PrmTxnReturnEvent> events = returnEventRepository.findTop100ByOrderByReturnedAtDesc();
        List<Map<String, Object>> result = new ArrayList<>();
        for (PrmTxnReturnEvent ev : events) {
            List<PrmTxnReturnAdjustment> adjs = returnAdjustmentRepository.findByReturnEventId(ev.getId());
            String promoId = adjs.isEmpty() ? "P-101" : adjs.get(0).getPromotionId();

            if (effectiveCompanyId != null && effectiveCompanyId > 0) {
                boolean matchCompany = effectiveCompanyId.equals(ev.getCompanyId())
                        || allowedPromoIds.contains(promoId)
                        || allowedPromoCodes.contains(promoId);
                if (!matchCompany) continue;
            }

            String msgId = adjs.isEmpty() ? "Penyesuaian promo" : adjs.get(0).getMessage();

            Map<String, Object> row = new LinkedHashMap<>();
            row.put("returnNo", ev.getReturnNo());
            row.put("orderId", ev.getOrderId());
            row.put("returnedAt", ev.getReturnedAt().toLocalDate().toString());
            row.put("promoId", promoId);
            row.put("actionText", Map.of("id", msgId, "en", msgId));
            row.put("netRefund", ev.getNetRefundAmount());
            result.add(row);
        }
        return result;
    }

    public Map<String, Object> getAllMetadataReferences() {
        Map<String, Object> ref = new LinkedHashMap<>();
        ref.put("currencies", currencyRepository.findByIsActiveTrue());
        ref.put("locales", localeRepository.findByIsActiveTrue());
        ref.put("channels", channelRepository.findByIsActiveTrue());
        ref.put("promoTypes", promoTypeRepository.findByIsActiveTrueOrderByPhaseAscTypeCodeAsc());
        ref.put("benefitKinds", benefitKindRepository.findByIsActiveTrueOrderByPhaseAscKindAsc());
        ref.put("facts", factRepository.findByIsActiveTrueOrderByFactGroupAscFactKeyAsc());
        ref.put("stackingRules", stackingRuleRepository.findAll());
        ref.put("approvalMatrix", approvalMatrixRepository.findByCompanyIdAndIsActiveTrueOrderByPriorityDesc(1));
        return ref;
    }
}
