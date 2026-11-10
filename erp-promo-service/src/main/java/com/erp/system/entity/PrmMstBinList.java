package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_mst_bin_list", schema = "schema_promotion")
public class PrmMstBinList {

    @Id
    @Column(name = "list_id", length = 60)
    private String listId;

    @Column(name = "name", nullable = false, length = 150)
    private String name;

    @Column(name = "bank_name", length = 100)
    private String bankName;

    @Column(name = "description", columnDefinition = "text")
    private String description;

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
