package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_mst_locale", schema = "schema_promotion")
public class PrmMstLocale {

    @Id
    @Column(name = "locale", length = 15)
    private String locale;

    @Column(name = "name", nullable = false, length = 100)
    private String name;

    @Column(name = "fallback_locale", length = 15)
    private String fallbackLocale;

    @Column(name = "is_rtl", nullable = false)
    private Boolean isRtl = false;

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
