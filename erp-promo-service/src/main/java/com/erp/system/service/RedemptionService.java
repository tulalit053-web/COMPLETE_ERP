package com.erp.system.service;

import com.erp.system.dto.PromoEvaluateResponse;
import com.erp.system.dto.PromoRedeemRequest;
import com.erp.system.entity.PrmTxnPromotionBudget;
import com.erp.system.entity.PrmTxnRedemption;
import com.erp.system.entity.PrmTxnRedemptionLine;
import com.erp.system.repository.PrmTxnPromotionBudgetRepository;
import com.erp.system.repository.PrmTxnRedemptionLineRepository;
import com.erp.system.repository.PrmTxnRedemptionRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.*;

@Service
public class RedemptionService {

    private final PromoEngineService promoEngineService;
    private final PrmTxnRedemptionRepository redemptionRepository;
    private final PrmTxnRedemptionLineRepository redemptionLineRepository;
    private final PrmTxnPromotionBudgetRepository budgetRepository;
    private final ObjectMapper objectMapper;

    public RedemptionService(
            PromoEngineService promoEngineService,
            PrmTxnRedemptionRepository redemptionRepository,
            PrmTxnRedemptionLineRepository redemptionLineRepository,
            PrmTxnPromotionBudgetRepository budgetRepository,
            ObjectMapper objectMapper) {
        this.promoEngineService = promoEngineService;
        this.redemptionRepository = redemptionRepository;
        this.redemptionLineRepository = redemptionLineRepository;
        this.budgetRepository = budgetRepository;
        this.objectMapper = objectMapper;
    }

    @Transactional
    public Map<String, Object> reserve(PromoRedeemRequest req) {
        return processRedemption(req, "reserved");
    }

    @Transactional
    public Map<String, Object> redeem(PromoRedeemRequest req) {
        return processRedemption(req, "confirmed");
    }

    private Map<String, Object> processRedemption(PromoRedeemRequest req, String targetStatus) {
        String idemKey = Optional.ofNullable(req.getIdempotencyKey())
                .orElse(targetStatus + "-" + req.getOrderId());

        Optional<PrmTxnRedemption> existing = redemptionRepository.findByIdempotencyKey(idemKey);
        if (existing.isPresent()) {
            PrmTxnRedemption r = existing.get();
            return Map.of(
                    "status", r.getStatus(),
                    "idempotentReplay", true,
                    "redemptionNo", r.getRedemptionNo(),
                    "orderId", r.getOrderId(),
                    "discountAmount", r.getDiscountAmount()
            );
        }

        PromoEvaluateResponse eval = promoEngineService.evaluate(req.getEvaluationInput());
        List<Map<String, Object>> savedRedemptions = new ArrayList<>();
        int idx = 1;

        for (PromoEvaluateResponse.AppliedPromo applied : eval.getApplied()) {
            long amountBase = applied.getDiscount();
            budgetRepository.findById(applied.getPromoId()).orElseGet(() -> {
                PrmTxnPromotionBudget b = new PrmTxnPromotionBudget();
                b.setPromotionId(applied.getPromoId());
                b.setCurrency("IDR");
                return budgetRepository.save(b);
            });

            int updated = "reserved".equals(targetStatus)
                    ? budgetRepository.tryReserveAtomically(applied.getPromoId(), amountBase)
                    : budgetRepository.tryDirectRedeemAtomically(applied.getPromoId(), amountBase);

            if (updated == 0) {
                throw new IllegalStateException("QUOTA_OR_BUDGET_EXHAUSTED for promotion " + applied.getPromoId());
            }

            PrmTxnRedemption redemption = new PrmTxnRedemption();
            redemption.setRedemptionNo("RDM-" + req.getOrderId() + "-" + idx);
            redemption.setPromotionId(applied.getPromoId());
            redemption.setPromotionVersion(Optional.ofNullable(applied.getVersion()).orElse(1));
            redemption.setOrderId(req.getOrderId());
            redemption.setCustomerId(req.getEvaluationInput().getCustomer() != null
                    ? req.getEvaluationInput().getCustomer().getId() : null);
            redemption.setChannel(Optional.ofNullable(req.getEvaluationInput().getContext().getChannel()).orElse("web"));
            redemption.setStoreId(req.getEvaluationInput().getContext().getStoreId());
            redemption.setLocale(Optional.ofNullable(eval.getLocale()).orElse("id-ID"));
            redemption.setCurrency(Optional.ofNullable(eval.getCurrency()).orElse("IDR"));
            redemption.setFxRateToBase(BigDecimal.ONE);
            redemption.setDiscountAmount(applied.getDiscount());
            redemption.setDiscountAmountBase(amountBase);
            redemption.setShippingSubsidyAmount("shipping".equals(applied.getGroup()) ? applied.getDiscount() : 0L);
            redemption.setBenefitSnapshotJson(toJson(applied));
            redemption.setFundingSnapshotJson(toJson(Optional.ofNullable(applied.getFunding()).orElse(List.of())));
            redemption.setInputSnapshotJson(toJson(req.getEvaluationInput()));
            redemption.setStatus(targetStatus);
            if ("reserved".equals(targetStatus)) {
                int ttl = Optional.ofNullable(req.getReserveTtlMinutes()).orElse(15);
                redemption.setReserveExpiresAt(OffsetDateTime.now().plusMinutes(ttl));
            } else {
                redemption.setConfirmedAt(OffsetDateTime.now());
            }
            redemption.setIdempotencyKey(idx == 1 ? idemKey : idemKey + "-" + idx);

            PrmTxnRedemption saved = redemptionRepository.save(redemption);

            // Simpan alokasi per baris item (redemption_lines - wajib untuk retur)
            for (PromoEvaluateResponse.LineBreakdown lb : eval.getLineBreakdowns()) {
                PrmTxnRedemptionLine line = new PrmTxnRedemptionLine();
                line.setRedemptionId(saved.getId());
                line.setOrderId(req.getOrderId());
                line.setOrderLineId(lb.getLineId());
                line.setPromotionId(applied.getPromoId());
                line.setPromotionVersion(Optional.ofNullable(applied.getVersion()).orElse(1));
                line.setSku(lb.getSku());
                line.setQty(lb.getQty());
                line.setReturnedQty(0);
                line.setCurrency(saved.getCurrency());
                line.setUnitListPrice(lb.getUnitListPrice());
                line.setLineGrossAmount(lb.getLineGrossAmount());
                line.setDiscountAmount(lb.getDiscountAmount());
                line.setLineNetAmount(lb.getLineNetAmount());
                line.setAllocatedFundingJson(saved.getFundingSnapshotJson());
                redemptionLineRepository.save(line);
            }

            savedRedemptions.add(Map.of(
                    "redemptionNo", saved.getRedemptionNo(),
                    "promoId", saved.getPromotionId(),
                    "discountAmount", saved.getDiscountAmount(),
                    "status", saved.getStatus()
            ));
            idx++;
        }

        return Map.of(
                "orderId", req.getOrderId(),
                "status", targetStatus,
                "redemptions", savedRedemptions,
                "evaluation", eval
        );
    }

    @Transactional
    public Map<String, Object> rollback(String orderId, String idempotencyKey) {
        List<PrmTxnRedemption> redemptions = redemptionRepository.findByOrderId(orderId);
        int reversedCount = 0;
        for (PrmTxnRedemption r : redemptions) {
            if ("reversed".equals(r.getStatus())) continue;
            if ("reserved".equals(r.getStatus())) {
                budgetRepository.releaseReservationAtomically(r.getPromotionId(), r.getDiscountAmountBase());
            } else if ("confirmed".equals(r.getStatus())) {
                budgetRepository.restoreUsedAtomically(r.getPromotionId(), 1, r.getDiscountAmountBase());
            }
            r.setStatus("reversed");
            r.setReversedAt(OffsetDateTime.now());
            redemptionRepository.save(r);
            reversedCount++;
        }
        return Map.of(
                "orderId", orderId,
                "reversedRedemptions", reversedCount,
                "status", "reversed"
        );
    }

    public Map<String, Object> getOrderPromoBreakdown(String orderId) {
        List<PrmTxnRedemption> redemptions = redemptionRepository.findByOrderId(orderId);
        List<PrmTxnRedemptionLine> lines = redemptionLineRepository.findByOrderId(orderId);
        return Map.of(
                "orderId", orderId,
                "redemptions", redemptions,
                "lines", lines
        );
    }

    private String toJson(Object obj) {
        try {
            return objectMapper.writeValueAsString(obj);
        } catch (Exception e) {
            return "{}";
        }
    }
}
