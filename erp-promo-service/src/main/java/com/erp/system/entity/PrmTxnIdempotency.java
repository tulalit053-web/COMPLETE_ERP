package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_txn_idempotency", schema = "schema_promotion")
public class PrmTxnIdempotency {

    @Id
    @Column(name = "idempotency_key", length = 120)
    private String idempotencyKey;

    @Column(name = "operation", nullable = false, length = 60)
    private String operation;

    @Column(name = "request_hash", nullable = false, length = 128)
    private String requestHash;

    @Column(name = "response_status", nullable = false)
    private Integer responseStatus;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "response_body_json", nullable = false, columnDefinition = "jsonb")
    private String responseBodyJson;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @Column(name = "expires_at", nullable = false)
    private OffsetDateTime expiresAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = OffsetDateTime.now();
        if (expiresAt == null) expiresAt = createdAt.plusDays(7);
    }
}
