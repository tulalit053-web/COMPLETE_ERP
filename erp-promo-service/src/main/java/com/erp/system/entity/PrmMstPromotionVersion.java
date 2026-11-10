package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_mst_promotion_version", schema = "schema_promotion")
public class PrmMstPromotionVersion {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "promotion_id", nullable = false, length = 64)
    private String promotionId;

    @Column(name = "version", nullable = false)
    private Integer version;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "config_json", nullable = false, columnDefinition = "jsonb")
    private String configJson;

    @Column(name = "config_hash", nullable = false, length = 128)
    private String configHash;

    @Column(name = "start_at", nullable = false)
    private OffsetDateTime startAt;

    @Column(name = "end_at", nullable = false)
    private OffsetDateTime endAt;

    @Column(name = "expires_at", nullable = false)
    private OffsetDateTime expiresAt;

    @Column(name = "approval_status", nullable = false, length = 30)
    private String approvalStatus = "draft";

    @Column(name = "changed_by", nullable = false, length = 100)
    private String changedBy;

    @Column(name = "changed_at", nullable = false)
    private OffsetDateTime changedAt;

    @Column(name = "change_reason", columnDefinition = "text")
    private String changeReason;

    @PrePersist
    protected void onCreate() {
        if (changedAt == null) changedAt = OffsetDateTime.now();
    }
}
