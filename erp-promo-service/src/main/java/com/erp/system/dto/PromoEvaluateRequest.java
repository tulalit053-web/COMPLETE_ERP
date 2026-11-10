package com.erp.system.dto;

import lombok.Data;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@Data
public class PromoEvaluateRequest {

    private CustomerInput customer = new CustomerInput();
    private ContextInput context = new ContextInput();
    private CartInput cart = new CartInput();
    private PaymentInput payment = new PaymentInput();
    private Map<String, Object> tradein;

    @Data
    public static class CustomerInput {
        private String id;
        private String tier = "REGULAR";
        private Boolean isNew = false;
        private List<String> segment = new ArrayList<>();
        private Integer birthdayMonth;
        private Integer orderCount = 0;
        private Long lifetimeSpend = 0L;
        private Integer daysSinceLastOrder = 0;
        private String region;
        private Boolean isEmployee = false;
        private Boolean marketingConsent = true;
    }

    @Data
    public static class ContextInput {
        private String channel = "web";
        private String locale = "id-ID";
        private String currency = "IDR";
        private String storeId = "ONLINE";
        private String platform = "Web";
        private String now;
        private String couponCode;
    }

    @Data
    public static class CartInput {
        private List<CartItemInput> items = new ArrayList<>();
        private Long shippingFee = 0L;
        private Double weight = 0.0;
    }

    @Data
    public static class CartItemInput {
        private String lineId;
        private String sku;
        private String name;
        private Integer qty = 1;
        private Long unitPrice = 0L;
        private String category;
        private String brand;
        private List<String> tags = new ArrayList<>();
        private Boolean alreadyDiscounted = false;
    }

    @Data
    public static class PaymentInput {
        private String method;
        private String provider;
        private String cardBin;
        private String cardNetwork;
        private String cardType;
        private Integer installmentTenor = 0;
    }
}
