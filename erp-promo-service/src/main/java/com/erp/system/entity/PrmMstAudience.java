package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_mst_audience", schema = "schema_promotion")
public class PrmMstAudience {

    @Id
    @Column(name = "id", length = 64)
    private String id;

    @Column(name = "name", nullable = false, length = 150)
    private String name;

    @Column(name = "type", nullable = false, length = 20)
    private String type;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "rule_json", columnDefinition = "jsonb")
    private String ruleJson;

    @Column(name = "source", nullable = false, length = 60)
    private String source = "CRM";

    @Column(name = "refresh_schedule", length = 60)
    private String refreshSchedule;

    @Column(name = "estimated_size", nullable = false)
    private Integer estimatedSize = 0;

    @Column(name = "is_active", nullable = false)
    private Boolean isActive = true;

    @Column(name = "created_datetime", nullable = false, updatable = false)
    private OffsetDateTime createdDatetime;

    @Column(name = "modified_datetime", nullable = false)
    private OffsetDateTime modifiedDatetime;

    @PrePersist
    protected void onCreate() {
        OffsetDateTime now = OffsetDateTime.now();
        if (createdDatetime == null) createdDatetime = now;
        if (modifiedDatetime == null) modifiedDatetime = now;
    }

    @PreUpdate
    protected void onUpdate() {
        modifiedDatetime = OffsetDateTime.now();
    }
}
