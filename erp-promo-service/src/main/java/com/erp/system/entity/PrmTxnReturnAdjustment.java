package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_txn_return_adjustment", schema = "schema_promotion")
public class PrmTxnReturnAdjustment {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "return_event_id", nullable = false)
    private Long returnEventId;

    @Column(name = "redemption_id")
    private Long redemptionId;

    @Column(name = "promotion_id", nullable = false, length = 64)
    private String promotionId;

    @Column(name = "action", nullable = false, length = 30)
    private String action;

    @Column(name = "amount", nullable = false)
    private Long amount;

    @Column(name = "currency", nullable = false, length = 3)
    private String currency = "IDR";

    @Column(name = "reason_code", nullable = false, length = 80)
    private String reasonCode;

    @Column(name = "message", columnDefinition = "text")
    private String message;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "quota_restored_json", nullable = false, columnDefinition = "jsonb")
    private String quotaRestoredJson = "{}";

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "clawback_json", nullable = false, columnDefinition = "jsonb")
    private String clawbackJson = "[]";

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "funding_reversal_json", nullable = false, columnDefinition = "jsonb")
    private String fundingReversalJson = "[]";

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = OffsetDateTime.now();
    }
}
