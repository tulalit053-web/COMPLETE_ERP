package com.erp.system.dto;

import lombok.Data;

import java.util.List;

@Data
public class PromoRedeemRequest {
    private String orderId;
    private String idempotencyKey;
    private Integer reserveTtlMinutes = 15;
    private PromoEvaluateRequest evaluationInput;
}
