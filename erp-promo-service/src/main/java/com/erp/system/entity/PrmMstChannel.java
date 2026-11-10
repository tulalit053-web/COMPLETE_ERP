package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;
import java.util.List;

@Data
@Entity
@Table(name = "prm_mst_channel", schema = "schema_promotion")
public class PrmMstChannel {

    @Id
    @Column(name = "channel", length = 50)
    private String channel;

    @Column(name = "name", nullable = false, length = 100)
    private String name;

    @Column(name = "channel_type", nullable = false, length = 30)
    private String channelType;

    @Column(name = "evaluation_mode", nullable = false, length = 20)
    private String evaluationMode = "realtime";

    @Column(name = "price_trust_mode", nullable = false, length = 20)
    private String priceTrustMode = "engine_fetch";

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "capabilities_json", nullable = false, columnDefinition = "jsonb")
    private String capabilitiesJson = "{}";

    @JdbcTypeCode(SqlTypes.ARRAY)
    @Column(name = "currencies", nullable = false, columnDefinition = "varchar(3)[]")
    private List<String> currencies = List.of("IDR");

    @JdbcTypeCode(SqlTypes.ARRAY)
    @Column(name = "locales", nullable = false, columnDefinition = "varchar(15)[]")
    private List<String> locales = List.of("id-ID");

    @Column(name = "is_active", nullable = false)
    private Boolean isActive = true;

    @Column(name = "created_datetime", nullable = false, updatable = false)
    private OffsetDateTime createdDatetime;

    @Column(name = "created_by", length = 100)
    private String createdBy;

    @PrePersist
    protected void onCreate() {
        if (createdDatetime == null) createdDatetime = OffsetDateTime.now();
    }
}
