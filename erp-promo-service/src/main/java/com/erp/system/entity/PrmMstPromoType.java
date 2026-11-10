package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_mst_promo_type", schema = "schema_promotion")
public class PrmMstPromoType {

    @Id
    @Column(name = "type_code", length = 40)
    private String typeCode;

    @Column(name = "name", nullable = false, length = 100)
    private String name;

    @Column(name = "name_en", length = 100)
    private String nameEn;

    @Column(name = "default_benefit_kind", length = 40)
    private String defaultBenefitKind;

    @Column(name = "default_group", length = 30)
    private String defaultGroup;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "config_schema", columnDefinition = "jsonb")
    private String configSchema;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "default_template", columnDefinition = "jsonb")
    private String defaultTemplate;

    @Column(name = "business_goal", length = 200)
    private String businessGoal;

    @Column(name = "phase", nullable = false)
    private Short phase = 1;

    @Column(name = "is_active", nullable = false)
    private Boolean isActive = true;

    @Column(name = "created_datetime", nullable = false, updatable = false)
    private OffsetDateTime createdDatetime;

    @PrePersist
    protected void onCreate() {
        if (createdDatetime == null) createdDatetime = OffsetDateTime.now();
    }
}
