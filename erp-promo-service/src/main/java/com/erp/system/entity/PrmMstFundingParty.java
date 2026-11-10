package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_mst_funding_party", schema = "schema_promotion")
public class PrmMstFundingParty {

    @Id
    @Column(name = "party_code", length = 50)
    private String partyCode;

    @Column(name = "company_id")
    private Integer companyId;

    @Column(name = "name", nullable = false, length = 150)
    private String name;

    @Column(name = "party_type", nullable = false, length = 30)
    private String partyType;

    @Column(name = "external_ref", length = 100)
    private String externalRef;

    @Column(name = "is_active", nullable = false)
    private Boolean isActive = true;

    @Column(name = "created_datetime", nullable = false, updatable = false)
    private OffsetDateTime createdDatetime;

    @PrePersist
    protected void onCreate() {
        if (createdDatetime == null) createdDatetime = OffsetDateTime.now();
    }
}
