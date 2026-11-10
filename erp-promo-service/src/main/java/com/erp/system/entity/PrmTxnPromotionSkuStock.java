package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_txn_promotion_sku_stock", schema = "schema_promotion")
public class PrmTxnPromotionSkuStock {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "promotion_id", nullable = false, length = 64)
    private String promotionId;

    @Column(name = "sku", nullable = false, length = 80)
    private String sku;

    @Column(name = "stock_cap", nullable = false)
    private Integer stockCap;

    @Column(name = "stock_reserved", nullable = false)
    private Integer stockReserved = 0;

    @Column(name = "stock_used", nullable = false)
    private Integer stockUsed = 0;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    @PrePersist
    @PreUpdate
    protected void onSave() {
        updatedAt = OffsetDateTime.now();
    }
}
