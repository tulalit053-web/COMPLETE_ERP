package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.LocalDate;
import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_txn_promotion_budget", schema = "schema_promotion")
public class PrmTxnPromotionBudget {

    @Id
    @Column(name = "promotion_id", length = 64)
    private String promotionId;

    @Column(name = "currency", nullable = false, length = 3)
    private String currency = "IDR";

    @Column(name = "budget_cap")
    private Long budgetCap;

    @Column(name = "budget_reserved", nullable = false)
    private Long budgetReserved = 0L;

    @Column(name = "budget_used", nullable = false)
    private Long budgetUsed = 0L;

    @Column(name = "redemption_cap")
    private Integer redemptionCap;

    @Column(name = "redemption_reserved", nullable = false)
    private Integer redemptionReserved = 0;

    @Column(name = "redemption_used", nullable = false)
    private Integer redemptionUsed = 0;

    @Column(name = "daily_quota_cap")
    private Integer dailyQuotaCap;

    @Column(name = "daily_quota_used", nullable = false)
    private Integer dailyQuotaUsed = 0;

    @Column(name = "daily_quota_date")
    private LocalDate dailyQuotaDate;

    @Column(name = "net_of_returns", nullable = false)
    private Boolean netOfReturns = true;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    @PrePersist
    @PreUpdate
    protected void onSave() {
        updatedAt = OffsetDateTime.now();
    }
}
