package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_mst_promotion_translation", schema = "schema_promotion")
public class PrmMstPromotionTranslation {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "promotion_id", nullable = false, length = 64)
    private String promotionId;

    @Column(name = "version", nullable = false)
    private Integer version = 1;

    @Column(name = "locale", nullable = false, length = 15)
    private String locale;

    @Column(name = "name", nullable = false, length = 200)
    private String name;

    @Column(name = "badge", length = 80)
    private String badge;

    @Column(name = "short_text", length = 300)
    private String shortText;

    @Column(name = "terms_and_conditions", columnDefinition = "text")
    private String termsAndConditions;

    @Column(name = "banner_url", length = 500)
    private String bannerUrl;

    @Column(name = "translation_status", nullable = false, length = 25)
    private String translationStatus = "draft";

    @Column(name = "reviewed_by", length = 100)
    private String reviewedBy;

    @Column(name = "reviewed_at")
    private OffsetDateTime reviewedAt;

    @Column(name = "modified_datetime", nullable = false)
    private OffsetDateTime modifiedDatetime;

    @PrePersist
    @PreUpdate
    protected void onSave() {
        modifiedDatetime = OffsetDateTime.now();
    }
}
