package com.erp.system.dto;

import lombok.Data;

import java.util.ArrayList;
import java.util.List;

@Data
public class PromoReturnRequest {
    private String orderId;
    private String returnType = "partial_return";
    private String channel = "pos";
    private String sourceSystem = "OMS";
    private String reasonCode = "CUSTOMER_RETURN";
    private String locale = "id-ID";
    private String returnedAt;
    private String idempotencyKey;
    private Long externalRefundAmount;
    private List<ReturnLineItem> lines = new ArrayList<>();

    @Data
    public static class ReturnLineItem {
        private String lineId;
        private String sku;
        private Integer qty = 1;
        private String reasonCode;
    }
}
