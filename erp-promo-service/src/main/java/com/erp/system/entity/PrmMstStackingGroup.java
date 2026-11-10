package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_mst_stacking_group", schema = "schema_promotion")
public class PrmMstStackingGroup {

    @Id
    @Column(name = "group_code", length = 30)
    private String groupCode;

    @Column(name = "name", nullable = false, length = 100)
    private String name;

    @Column(name = "pipeline_step", nullable = false)
    private Short pipelineStep;

    @Column(name = "description", length = 500)
    private String description;

    @Column(name = "created_datetime", nullable = false, updatable = false)
    private OffsetDateTime createdDatetime;

    @Column(name = "created_by", length = 100)
    private String createdBy;

    @PrePersist
    protected void onCreate() {
        if (createdDatetime == null) createdDatetime = OffsetDateTime.now();
    }
}
