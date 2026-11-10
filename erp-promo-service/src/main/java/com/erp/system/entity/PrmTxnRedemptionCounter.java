package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.OffsetDateTime;

@Data
@Entity
@IdClass(PrmTxnRedemptionCounterId.class)
@Table(name = "prm_txn_redemption_counter", schema = "schema_promotion")
public class PrmTxnRedemptionCounter {

    @Id
    @Column(name = "promotion_id", length = 64)
    private String promotionId;

    @Id
    @Column(name = "subject_type", length = 30)
    private String subjectType;

    @Id
    @Column(name = "subject_key", length = 150)
    private String subjectKey;

    @Column(name = "reserved_count", nullable = false)
    private Integer reservedCount = 0;

    @Column(name = "confirmed_count", nullable = false)
    private Integer confirmedCount = 0;

    @Column(name = "last_redeemed_at", nullable = false)
    private OffsetDateTime lastRedeemedAt;

    @PrePersist
    @PreUpdate
    protected void onSave() {
        lastRedeemedAt = OffsetDateTime.now();
    }
}
