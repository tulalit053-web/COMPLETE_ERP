package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_mst_data_source", schema = "schema_promotion")
public class PrmMstDataSource {

    @Id
    @Column(name = "source_id", length = 60)
    private String sourceId;

    @Column(name = "domain", nullable = false, length = 30)
    private String domain;

    @Column(name = "source_type", nullable = false, length = 30)
    private String sourceType;

    @Column(name = "base_url", length = 300)
    private String baseUrl;

    @Column(name = "auth_ref", length = 150)
    private String authRef;

    @Column(name = "mapping_id", length = 80)
    private String mappingId;

    @Column(name = "priority", nullable = false)
    private Short priority = 1;

    @Column(name = "timeout_ms", nullable = false)
    private Integer timeoutMs = 500;

    @Column(name = "cache_ttl_seconds", nullable = false)
    private Integer cacheTtlSeconds = 120;

    @Column(name = "failure_policy", nullable = false, length = 25)
    private String failurePolicy = "fail_closed";

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "applies_to_json", nullable = false, columnDefinition = "jsonb")
    private String appliesToJson = "{}";

    @Column(name = "last_health_status", nullable = false, length = 20)
    private String lastHealthStatus = "UP";

    @Column(name = "last_health_checked_at")
    private OffsetDateTime lastHealthCheckedAt;

    @Column(name = "is_active", nullable = false)
    private Boolean isActive = true;

    @Column(name = "modified_datetime", nullable = false)
    private OffsetDateTime modifiedDatetime;

    @PrePersist
    @PreUpdate
    protected void onSave() {
        modifiedDatetime = OffsetDateTime.now();
    }
}
