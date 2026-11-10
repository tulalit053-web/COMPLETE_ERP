package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_txn_change_request", schema = "schema_promotion")
public class PrmTxnChangeRequest {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "request_no", nullable = false, unique = true, length = 50)
    private String requestNo;

    @Column(name = "entity_type", nullable = false, length = 40)
    private String entityType = "PROMOTION";

    @Column(name = "promotion_id", length = 64)
    private String promotionId;

    @Column(name = "from_version")
    private Integer fromVersion;

    @Column(name = "to_version", nullable = false)
    private Integer toVersion;

    @Column(name = "config_hash", nullable = false, length = 128)
    private String configHash;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "payload_json", nullable = false, columnDefinition = "jsonb")
    private String payloadJson;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "simulation_result_json", columnDefinition = "jsonb")
    private String simulationResultJson;

    @Column(name = "matched_matrix_id")
    private Long matchedMatrixId;

    @Column(name = "required_levels", nullable = false)
    private Short requiredLevels = 1;

    @Column(name = "current_level", nullable = false)
    private Short currentLevel = 1;

    @Column(name = "status", nullable = false, length = 30)
    private String status = "pending";

    @Column(name = "maker_id", nullable = false, length = 100)
    private String makerId;

    @Column(name = "submitted_at", nullable = false)
    private OffsetDateTime submittedAt;

    @Column(name = "maker_note", columnDefinition = "text")
    private String makerNote;

    @Column(name = "expires_at")
    private OffsetDateTime expiresAt;

    @Column(name = "completed_at")
    private OffsetDateTime completedAt;

    @PrePersist
    protected void onCreate() {
        if (submittedAt == null) submittedAt = OffsetDateTime.now();
    }
}
