package com.erp.system.controller;

import com.erp.system.dto.*;
import com.erp.system.service.PromoEngineService;
import com.erp.system.service.RedemptionService;
import com.erp.system.service.ReturnEngineService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
public class PromoEngineController {

    private final PromoEngineService promoEngineService;
    private final RedemptionService redemptionService;
    private final ReturnEngineService returnEngineService;

    public PromoEngineController(
            PromoEngineService promoEngineService,
            RedemptionService redemptionService,
            ReturnEngineService returnEngineService) {
        this.promoEngineService = promoEngineService;
        this.redemptionService = redemptionService;
        this.returnEngineService = returnEngineService;
    }

    @PostMapping("/v1/promos/evaluate")
    public ResponseEntity<PromoEvaluateResponse> evaluate(@RequestBody PromoEvaluateRequest request) {
        return ResponseEntity.ok(promoEngineService.evaluate(request));
    }

    @PostMapping("/v1/promos/reserve")
    public ResponseEntity<Map<String, Object>> reserve(@RequestBody PromoRedeemRequest request) {
        return ResponseEntity.ok(redemptionService.reserve(request));
    }

    @PostMapping("/v1/promos/redeem")
    public ResponseEntity<Map<String, Object>> redeem(@RequestBody PromoRedeemRequest request) {
        return ResponseEntity.ok(redemptionService.redeem(request));
    }

    @PostMapping("/v1/promos/rollback")
    public ResponseEntity<Map<String, Object>> rollback(
            @RequestParam("orderId") String orderId,
            @RequestParam(value = "idempotencyKey", required = false) String idempotencyKey) {
        return ResponseEntity.ok(redemptionService.rollback(orderId, idempotencyKey));
    }

    @GetMapping("/v1/orders/{orderId}/promo-breakdown")
    public ResponseEntity<Map<String, Object>> getOrderPromoBreakdown(@PathVariable("orderId") String orderId) {
        return ResponseEntity.ok(redemptionService.getOrderPromoBreakdown(orderId));
    }

    @PostMapping("/v1/returns/evaluate")
    public ResponseEntity<Map<String, Object>> evaluateReturn(@RequestBody PromoReturnRequest request) {
        return ResponseEntity.ok(returnEngineService.evaluateReturn(request));
    }

    @PostMapping("/v1/returns/commit")
    public ResponseEntity<Map<String, Object>> commitReturn(@RequestBody PromoReturnRequest request) {
        return ResponseEntity.ok(returnEngineService.commitReturn(request));
    }
}
