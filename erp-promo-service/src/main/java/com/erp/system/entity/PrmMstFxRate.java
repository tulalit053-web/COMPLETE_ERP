package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_mst_fx_rate", schema = "schema_promotion")
public class PrmMstFxRate {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "base_currency", nullable = false, length = 3)
    private String baseCurrency;

    @Column(name = "quote_currency", nullable = false, length = 3)
    private String quoteCurrency;

    @Column(name = "rate_type", nullable = false, length = 10)
    private String rateType = "mid";

    @Column(name = "rate", nullable = false, precision = 20, scale = 8)
    private BigDecimal rate;

    @Column(name = "effective_at", nullable = false)
    private OffsetDateTime effectiveAt;

    @Column(name = "source", nullable = false, length = 60)
    private String source = "treasury";

    @Column(name = "is_manual_override", nullable = false)
    private Boolean isManualOverride = false;

    @Column(name = "approved_by", length = 100)
    private String approvedBy;

    @Column(name = "is_stale", nullable = false)
    private Boolean isStale = false;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        OffsetDateTime now = OffsetDateTime.now();
        if (createdAt == null) createdAt = now;
        if (effectiveAt == null) effectiveAt = now;
    }
}
