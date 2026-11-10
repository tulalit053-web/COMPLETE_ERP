package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

@Data
@Entity
@IdClass(PrmMstSystemConfigId.class)
@Table(name = "prm_mst_system_config", schema = "schema_promotion")
public class PrmMstSystemConfig {

    @Id
    @Column(name = "config_key", length = 100)
    private String configKey;

    @Id
    @Column(name = "company_id", nullable = false)
    private Integer companyId = 0;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "config_value", nullable = false, columnDefinition = "jsonb")
    private String configValue;

    @Column(name = "description", length = 500)
    private String description;

    @Column(name = "requires_approval", nullable = false)
    private Boolean requiresApproval = true;

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
