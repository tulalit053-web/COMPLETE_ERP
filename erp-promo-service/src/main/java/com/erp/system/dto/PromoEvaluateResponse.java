package com.erp.system.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class PromoEvaluateResponse {

    @Builder.Default
    private List<AppliedPromo> applied = new ArrayList<>();

    @Builder.Default
    private List<RejectedPromo> rejected = new ArrayList<>();

    @Builder.Default
    private List<LineBreakdown> lineBreakdowns = new ArrayList<>();

    @Builder.Default
    private List<RewardEarned> rewards = new ArrayList<>();

    @Builder.Default
    private List<String> dataQuality = new ArrayList<>();

    private String currency;
    private String locale;
    private Totals totals;

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class AppliedPromo {
        private String promoId;
        private String code;
        private String name;
        private String type;
        private String group;
        private Integer version;
        private Long discount;
        private String target;
        private List<Map<String, Object>> funding;
    }

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class RejectedPromo {
        private String promoId;
        private String code;
        private String name;
        private String reason;
        private String message;
        private Map<String, Object> detail;
    }

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class LineBreakdown {
        private String lineId;
        private String sku;
        private Integer qty;
        private Long unitListPrice;
        private Long lineGrossAmount;
        private Long discountAmount;
        private Long lineNetAmount;
        private String appliedPromoId;
    }

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class RewardEarned {
        private String promoId;
        private String kind;
        private Long value;
        private String description;
    }

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class Totals {
        private Long subtotal;
        private Long itemDiscountTotal;
        private Long cartDiscountTotal;
        private Long tradeinCredit;
        private Long shippingFeeOriginal;
        private Long shippingDiscount;
        private Long shippingNet;
        private Long paymentDiscount;
        private Long discountTotal;
        private Long grandTotal;
    }
}
