package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_mst_approval_matrix", schema = "schema_promotion")
public class PrmMstApprovalMatrix {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "company_id", nullable = false)
    private Integer companyId = 1;

    @Column(name = "rule_code", nullable = false, length = 60)
    private String ruleCode;

    @Column(name = "name", nullable = false, length = 150)
    private String name;

    @Column(name = "priority", nullable = false)
    private Integer priority = 100;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "conditions_json", nullable = false, columnDefinition = "jsonb")
    private String conditionsJson;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "levels_json", nullable = false, columnDefinition = "jsonb")
    private String levelsJson;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "rules_json", nullable = false, columnDefinition = "jsonb")
    private String rulesJson;

    @Column(name = "version", nullable = false)
    private Integer version = 1;

    @Column(name = "is_active", nullable = false)
    private Boolean isActive = true;

    @Column(name = "created_datetime", nullable = false, updatable = false)
    private OffsetDateTime createdDatetime;

    @Column(name = "created_by", length = 100)
    private String createdBy;

    @Column(name = "modified_datetime", nullable = false)
    private OffsetDateTime modifiedDatetime;

    @Column(name = "modified_by", length = 100)
    private String modifiedBy;

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
