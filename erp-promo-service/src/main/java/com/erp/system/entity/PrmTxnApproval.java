package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_txn_approval", schema = "schema_promotion")
public class PrmTxnApproval {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "change_request_id", nullable = false)
    private Long changeRequestId;

    @Column(name = "promotion_id", length = 64)
    private String promotionId;

    @Column(name = "level", nullable = false)
    private Short level;

    @Column(name = "required_role", nullable = false, length = 60)
    private String requiredRole;

    @Column(name = "maker_id", nullable = false, length = 100)
    private String makerId;

    @Column(name = "approver_id", nullable = false, length = 100)
    private String approverId;

    @Column(name = "decision", nullable = false, length = 30)
    private String decision;

    @Column(name = "note", columnDefinition = "text")
    private String note;

    @Column(name = "config_hash", nullable = false, length = 128)
    private String configHash;

    @Column(name = "decided_at", nullable = false)
    private OffsetDateTime decidedAt;

    @PrePersist
    protected void onCreate() {
        if (decidedAt == null) decidedAt = OffsetDateTime.now();
    }
}
