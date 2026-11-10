package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_mst_return_policy_default", schema = "schema_promotion")
public class PrmMstReturnPolicyDefault {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "promo_category", nullable = false, unique = true, length = 40)
    private String promoCategory;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "policy_json", nullable = false, columnDefinition = "jsonb")
    private String policyJson;

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
