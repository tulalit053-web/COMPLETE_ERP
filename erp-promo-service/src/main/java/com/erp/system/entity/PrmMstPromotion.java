package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;
import java.util.List;

@Data
@Entity
@Table(name = "prm_mst_promotion", schema = "schema_promotion")
public class PrmMstPromotion {

    @Id
    @Column(name = "id", length = 64)
    private String id;

    @Column(name = "company_id", nullable = false)
    private Integer companyId = 1;

    @Column(name = "company_code", length = 50)
    private String companyCode = "COMP01";

    @Column(name = "code", nullable = false, length = 80)
    private String code;

    @Column(name = "name", nullable = false, length = 200)
    private String name;

    @Column(name = "description", columnDefinition = "text")
    private String description;

    @Column(name = "type", nullable = false, length = 40)
    private String type;

    @Column(name = "status", nullable = false, length = 30)
    private String status = "draft";

    @Column(name = "priority", nullable = false)
    private Integer priority = 0;

    @Column(name = "version", nullable = false)
    private Integer version = 1;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "config_json", nullable = false, columnDefinition = "jsonb")
    private String configJson;

    @Column(name = "config_hash", nullable = false, length = 128)
    private String configHash;

    @Column(name = "start_at", nullable = false)
    private OffsetDateTime startAt;

    @Column(name = "end_at", nullable = false)
    private OffsetDateTime endAt;

    @Column(name = "expires_at", nullable = false)
    private OffsetDateTime expiresAt;

    @Column(name = "checkout_grace_minutes", nullable = false)
    private Integer checkoutGraceMinutes = 15;

    @Column(name = "timezone", nullable = false, length = 60)
    private String timezone = "Asia/Jakarta";

    @Column(name = "base_currency", nullable = false, length = 3)
    private String baseCurrency = "IDR";

    @JdbcTypeCode(SqlTypes.ARRAY)
    @Column(name = "supported_currencies", nullable = false, columnDefinition = "varchar(3)[]")
    private List<String> supportedCurrencies = List.of("IDR");

    @Column(name = "amount_mode", nullable = false, length = 20)
    private String amountMode = "hybrid";

    @Column(name = "audience_type", nullable = false, length = 20)
    private String audienceType = "public";

    @Column(name = "default_locale", nullable = false, length = 15)
    private String defaultLocale = "id-ID";

    @JdbcTypeCode(SqlTypes.ARRAY)
    @Column(name = "required_locales", nullable = false, columnDefinition = "varchar(15)[]")
    private List<String> requiredLocales = List.of("id-ID");

    @Column(name = "maker_id", nullable = false, length = 100)
    private String makerId;

    @Column(name = "maker_at", nullable = false)
    private OffsetDateTime makerAt;

    @Column(name = "last_modified_by", length = 100)
    private String lastModifiedBy;

    @Column(name = "approval_status", nullable = false, length = 30)
    private String approvalStatus = "draft";

    @Column(name = "approved_version")
    private Integer approvedVersion;

    @Column(name = "approved_config_hash", length = 128)
    private String approvedConfigHash;

    @Column(name = "campaign_id", length = 80)
    private String campaignId;

    @JdbcTypeCode(SqlTypes.ARRAY)
    @Column(name = "tags", nullable = false, columnDefinition = "varchar(60)[]")
    private List<String> tags = List.of();

    @Column(name = "created_datetime", nullable = false, updatable = false)
    private OffsetDateTime createdDatetime;

    @Column(name = "modified_datetime", nullable = false)
    private OffsetDateTime modifiedDatetime;

    @PrePersist
    protected void onCreate() {
        OffsetDateTime now = OffsetDateTime.now();
        if (createdDatetime == null) createdDatetime = now;
        if (modifiedDatetime == null) modifiedDatetime = now;
        if (makerAt == null) makerAt = now;
    }

    @PreUpdate
    protected void onUpdate() {
        modifiedDatetime = OffsetDateTime.now();
    }
}
