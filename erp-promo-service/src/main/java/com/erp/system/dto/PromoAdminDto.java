package com.erp.system.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class PromoAdminDto {
    private String id;
    private Integer companyId;
    private String companyCode;
    private String code;
    private String name;
    private Map<String, String> localizedNames;
    private String description;
    private String type;
    private String status;
    private Integer priority;
    private Integer version;
    private OffsetDateTime startAt;
    private OffsetDateTime endAt;
    private OffsetDateTime expiresAt;
    private Long daysUntilExpiry;
    private String baseCurrency;
    private List<String> supportedCurrencies;
    private String defaultLocale;
    private List<String> requiredLocales;
    private String makerId;
    private String checkerId;
    private String approvalStatus;
    private Integer approvedVersion;
    private Long budgetCap;
    private Long budgetUsed;
    private Long budgetReserved;
    private Integer redemptionCap;
    private Integer redemptionUsed;
    private Double returnRate;
    private Double roi;
    private Map<String, Object> config;
    private List<Map<String, Object>> history;
}
