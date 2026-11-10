package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.OffsetDateTime;

@Data
@Entity
@IdClass(PrmMstStackingRuleId.class)
@Table(name = "prm_mst_stacking_rule", schema = "schema_promotion")
public class PrmMstStackingRule {

    @Id
    @Column(name = "group_a", length = 30)
    private String groupA;

    @Id
    @Column(name = "group_b", length = 30)
    private String groupB;

    @Column(name = "can_stack", nullable = false)
    private Boolean canStack;

    @Column(name = "version", nullable = false)
    private Integer version = 1;

    @Column(name = "modified_datetime", nullable = false)
    private OffsetDateTime modifiedDatetime;

    @Column(name = "modified_by", length = 100)
    private String modifiedBy;

    @PrePersist
    @PreUpdate
    protected void onSave() {
        modifiedDatetime = OffsetDateTime.now();
    }
}
