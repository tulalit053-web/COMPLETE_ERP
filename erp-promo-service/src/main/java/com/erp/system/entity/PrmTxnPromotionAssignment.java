package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_txn_promotion_assignment", schema = "schema_promotion")
public class PrmTxnPromotionAssignment {

    @Id
    @Column(name = "id", length = 64)
    private String id;

    @Column(name = "promotion_id", nullable = false, length = 64)
    private String promotionId;

    @Column(name = "customer_id", nullable = false, length = 100)
    private String customerId;

    @Column(name = "status", nullable = false, length = 20)
    private String status = "assigned";

    @Column(name = "is_holdout", nullable = false)
    private Boolean isHoldout = false;

    @Column(name = "valid_from", nullable = false)
    private OffsetDateTime validFrom;

    @Column(name = "valid_to", nullable = false)
    private OffsetDateTime validTo;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "overrides_json", nullable = false, columnDefinition = "jsonb")
    private String overridesJson = "{}";

    @Column(name = "source", nullable = false, length = 80)
    private String source = "CRM";

    @Column(name = "reason", columnDefinition = "text")
    private String reason;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        OffsetDateTime now = OffsetDateTime.now();
        if (createdAt == null) createdAt = now;
        if (updatedAt == null) updatedAt = now;
        if (validFrom == null) validFrom = now;
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = OffsetDateTime.now();
    }
}
