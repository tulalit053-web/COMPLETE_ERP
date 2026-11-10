package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;
import java.util.List;

@Data
@Entity
@Table(name = "prm_mst_fact", schema = "schema_promotion")
public class PrmMstFact {

    @Id
    @Column(name = "fact_key", length = 100)
    private String factKey;

    @Column(name = "fact_group", nullable = false, length = 30)
    private String factGroup;

    @Column(name = "data_type", nullable = false, length = 20)
    private String dataType;

    @Column(name = "source", nullable = false, length = 50)
    private String source = "request";

    @Column(name = "description", length = 500)
    private String description;

    @JdbcTypeCode(SqlTypes.ARRAY)
    @Column(name = "allowed_operators", columnDefinition = "varchar(20)[]")
    private List<String> allowedOperators;

    @Column(name = "is_active", nullable = false)
    private Boolean isActive = true;

    @Column(name = "created_datetime", nullable = false, updatable = false)
    private OffsetDateTime createdDatetime;

    @PrePersist
    protected void onCreate() {
        if (createdDatetime == null) createdDatetime = OffsetDateTime.now();
    }
}
