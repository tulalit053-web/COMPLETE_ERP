package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_mst_currency", schema = "schema_promotion")
public class PrmMstCurrency {

    @Id
    @Column(name = "code", length = 3)
    private String code;

    @Column(name = "name", nullable = false, length = 100)
    private String name;

    @Column(name = "symbol", length = 10)
    private String symbol;

    @Column(name = "minor_unit", nullable = false)
    private Short minorUnit = 0;

    @Column(name = "rounding_mode", nullable = false, length = 10)
    private String roundingMode = "round";

    @Column(name = "rounding_unit", nullable = false)
    private Long roundingUnit = 1L;

    @Column(name = "is_active", nullable = false)
    private Boolean isActive = true;

    @Column(name = "created_datetime", nullable = false, updatable = false)
    private OffsetDateTime createdDatetime;

    @Column(name = "created_by", length = 100)
    private String createdBy;

    @Column(name = "modified_datetime")
    private OffsetDateTime modifiedDatetime;

    @Column(name = "modified_by", length = 100)
    private String modifiedBy;

    @PrePersist
    protected void onCreate() {
        if (createdDatetime == null) createdDatetime = OffsetDateTime.now();
    }
}
