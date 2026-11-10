package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Data
@Entity
@Table(name = "prm_mst_benefit_kind", schema = "schema_promotion")
public class PrmMstBenefitKind {

    @Id
    @Column(name = "kind", length = 40)
    private String kind;

    @Column(name = "name", nullable = false, length = 100)
    private String name;

    @Column(name = "default_group", length = 30)
    private String defaultGroup;

    @Column(name = "is_post_transaction", nullable = false)
    private Boolean isPostTransaction = false;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "params_schema", columnDefinition = "jsonb")
    private String paramsSchema;

    @Column(name = "description", length = 500)
    private String description;

    @Column(name = "phase", nullable = false)
    private Short phase = 1;

    @Column(name = "is_active", nullable = false)
    private Boolean isActive = true;
}
