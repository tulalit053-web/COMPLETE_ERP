package com.erp.system.service;

import com.erp.system.dto.PromoEvaluateRequest;
import com.erp.system.dto.PromoEvaluateResponse;
import com.erp.system.dto.PromoReturnRequest;
import com.erp.system.entity.*;
import com.erp.system.repository.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.*;

@Service
public class ReturnEngineService {

    private final PrmTxnRedemptionRepository redemptionRepository;
    private final PrmTxnRedemptionLineRepository redemptionLineRepository;
    private final PrmTxnReturnEventRepository returnEventRepository;
    private final PrmTxnReturnAdjustmentRepository returnAdjustmentRepository;
    private final PrmMstPromotionRepository promotionRepository;
    private final PrmTxnPromotionBudgetRepository budgetRepository;
    private final PromoEngineService promoEngineService;
    private final ObjectMapper objectMapper;

    public ReturnEngineService(
            PrmTxnRedemptionRepository redemptionRepository,
            PrmTxnRedemptionLineRepository redemptionLineRepository,
            PrmTxnReturnEventRepository returnEventRepository,
            PrmTxnReturnAdjustmentRepository returnAdjustmentRepository,
            PrmMstPromotionRepository promotionRepository,
            PrmTxnPromotionBudgetRepository budgetRepository,
            PromoEngineService promoEngineService,
            ObjectMapper objectMapper) {
        this.redemptionRepository = redemptionRepository;
        this.redemptionLineRepository = redemptionLineRepository;
        this.returnEventRepository = returnEventRepository;
        this.returnAdjustmentRepository = returnAdjustmentRepository;
        this.promotionRepository = promotionRepository;
        this.budgetRepository = budgetRepository;
        this.promoEngineService = promoEngineService;
        this.objectMapper = objectMapper;
    }

    public Map<String, Object> evaluateReturn(PromoReturnRequest req) {
        return computeReturnImpact(req, false);
    }

    @Transactional
    public Map<String, Object> commitReturn(PromoReturnRequest req) {
        if (req.getIdempotencyKey() != null) {
            Optional<PrmTxnReturnEvent> existing = returnEventRepository.findByIdempotencyKey(req.getIdempotencyKey());
            if (existing.isPresent()) {
                PrmTxnReturnEvent ev = existing.get();
                return Map.of(
                        "returnNo", ev.getReturnNo(),
                        "orderId", ev.getOrderId(),
                        "netRefund", ev.getNetRefundAmount(),
                        "idempotentReplay", true
                );
            }
        }
        return computeReturnImpact(req, true);
    }

    private Map<String, Object> computeReturnImpact(PromoReturnRequest req, boolean commit) {
        List<PrmTxnRedemption> redemptions = redemptionRepository.findByOrderId(req.getOrderId());
        List<PrmTxnRedemptionLine> originalLines = redemptionLineRepository.findByOrderId(req.getOrderId());

        long grossReturnedValue = 0L;
        long totalOriginalGross = 0L;
        long totalOriginalDiscount = 0L;

        Map<String, Integer> returnQtyBySku = new HashMap<>();
        for (PromoReturnRequest.ReturnLineItem rl : req.getLines()) {
            returnQtyBySku.merge(rl.getSku(), Optional.ofNullable(rl.getQty()).orElse(1), Integer::sum);
        }

        List<PromoEvaluateRequest.CartItemInput> remainingItems = new ArrayList<>();
        for (PrmTxnRedemptionLine ol : originalLines) {
            totalOriginalGross += ol.getLineGrossAmount();
            totalOriginalDiscount += ol.getDiscountAmount();

            int retQty = Math.min(ol.getQty() - ol.getReturnedQty(), returnQtyBySku.getOrDefault(ol.getSku(), 0));
            grossReturnedValue += (long) retQty * ol.getUnitListPrice();

            int remQty = ol.getQty() - ol.getReturnedQty() - retQty;
            if (remQty > 0) {
                PromoEvaluateRequest.CartItemInput item = new PromoEvaluateRequest.CartItemInput();
                item.setLineId(ol.getOrderLineId());
                item.setSku(ol.getSku());
                item.setQty(remQty);
                item.setUnitPrice(ol.getUnitListPrice());
                remainingItems.add(item);
            }
        }

        long initialPaid = Math.max(0L, totalOriginalGross - totalOriginalDiscount);
        long remainingSubtotal = remainingItems.stream()
                .mapToLong(i -> (long) i.getQty() * i.getUnitPrice())
                .sum();

        // Evaluasi ulang basket sisa terhadap promo yang dipakai pada order asli (Bagian 13.4)
        List<PrmMstPromotion> originalPromos = promotionRepository.findAllById(
                redemptions.stream().map(PrmTxnRedemption::getPromotionId).distinct().toList()
        );

        long remainingDiscount = 0L;
        if (!remainingItems.isEmpty() && !originalPromos.isEmpty()) {
            PromoEvaluateRequest reEvalReq = new PromoEvaluateRequest();
            reEvalReq.getCart().setItems(remainingItems);
            reEvalReq.getContext().setChannel(req.getChannel());
            reEvalReq.getContext().setLocale(req.getLocale());
            PromoEvaluateResponse reEvalResp = promoEngineService.evaluateAgainstPromotions(reEvalReq, originalPromos);
            remainingDiscount = reEvalResp.getTotals().getDiscountTotal();
        }

        long remainingDue = Math.max(0L, remainingSubtotal - remainingDiscount);
        long previousRefunds = returnEventRepository.findByOrderIdOrderByReturnedAtAsc(req.getOrderId())
                .stream()
                .mapToLong(PrmTxnReturnEvent::getNetRefundAmount)
                .sum();

        // Rumus dasar refund (Bagian 13.1):
        // refund = total_dibayar_awal - total_yang_seharusnya_dibayar_untuk_basket_sisa - refund_sebelumnya
        long netRefund = !originalLines.isEmpty()
                ? Math.max(0L, initialPaid - remainingDue - previousRefunds)
                : grossReturnedValue;
        long promoAdjustment = netRefund - grossReturnedValue;

        List<Map<String, Object>> adjustments = new ArrayList<>();
        String primaryPromoId = redemptions.isEmpty() ? "P-101" : redemptions.get(0).getPromotionId();
        if (promoAdjustment != 0 || !redemptions.isEmpty()) {
            adjustments.add(Map.of(
                    "promo_id", primaryPromoId,
                    "action", remainingDiscount == 0 ? "REVOKED" : "RECOMPUTED",
                    "reason_code", remainingDiscount == 0 ? "THRESHOLD_NOT_MET_AFTER_RETURN" : "BXGY_PAIR_BROKEN_ON_RETURN",
                    "message", remainingDiscount == 0
                            ? "Keranjang sisa dihitung ulang: diskon dicabut"
                            : "Keranjang sisa dihitung ulang sesuai kuantitas sisa",
                    "amount", promoAdjustment
            ));
        }

        Map<String, Object> recomputedMap = Map.of(
                "remaining_subtotal", remainingSubtotal,
                "remaining_discount", remainingDiscount,
                "remaining_due", remainingDue
        );

        String returnNo = "RET-" + (System.currentTimeMillis() % 100000);
        if (commit) {
            PrmTxnReturnEvent ev = new PrmTxnReturnEvent();
            ev.setReturnNo(returnNo);
            ev.setOrderId(req.getOrderId());
            ev.setReturnType(Optional.ofNullable(req.getReturnType()).orElse("partial_return"));
            ev.setChannel(Optional.ofNullable(req.getChannel()).orElse("pos"));
            ev.setSourceSystem(Optional.ofNullable(req.getSourceSystem()).orElse("OMS"));
            ev.setReasonCode(Optional.ofNullable(req.getReasonCode()).orElse("CUSTOMER_RETURN"));
            ev.setLocale(Optional.ofNullable(req.getLocale()).orElse("id-ID"));
            ev.setCurrency("IDR");
            ev.setFxRateUsed(BigDecimal.ONE);
            ev.setReturnedLinesJson(toJson(req.getLines()));
            ev.setRecomputedBasketJson(toJson(recomputedMap));
            ev.setGrossItemValue(grossReturnedValue);
            ev.setPromoAdjustmentAmount(promoAdjustment);
            ev.setNetRefundAmount(netRefund);
            ev.setExternalRefundAmount(req.getExternalRefundAmount());
            ev.setMismatchFlag(req.getExternalRefundAmount() != null && !req.getExternalRefundAmount().equals(netRefund));
            ev.setStatus("committed");
            ev.setIdempotencyKey(Optional.ofNullable(req.getIdempotencyKey()).orElse("idem-" + returnNo));
            ev.setReturnedAt(OffsetDateTime.now());
            PrmTxnReturnEvent savedEv = returnEventRepository.save(ev);

            PrmTxnReturnAdjustment adj = new PrmTxnReturnAdjustment();
            adj.setReturnEventId(savedEv.getId());
            adj.setPromotionId(primaryPromoId);
            adj.setAction(remainingDiscount == 0 ? "REVOKED" : "RECOMPUTED");
            adj.setAmount(netRefund);
            adj.setCurrency("IDR");
            adj.setReasonCode("THRESHOLD_NOT_MET_AFTER_RETURN");
            adj.setMessage("Keranjang sisa dihitung ulang: diskon disesuaikan");
            returnAdjustmentRepository.save(adj);

            if (remainingItems.isEmpty()) {
                budgetRepository.restoreUsedAtomically(primaryPromoId, 1, Math.abs(promoAdjustment));
            }
        }

        return Map.of(
                "return_no", returnNo,
                "order_id", req.getOrderId(),
                "currency", "IDR",
                "locale", Optional.ofNullable(req.getLocale()).orElse("id-ID"),
                "recomputed", recomputedMap,
                "refund", Map.of(
                        "gross_item_value", grossReturnedValue,
                        "promo_adjustment", promoAdjustment,
                        "net_refund", netRefund
                ),
                "adjustments", adjustments,
                "committed", commit
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
