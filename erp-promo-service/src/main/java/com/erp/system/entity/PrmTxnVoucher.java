package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_txn_voucher", schema = "schema_promotion")
public class PrmTxnVoucher {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "promotion_id", nullable = false, length = 64)
    private String promotionId;

    @Column(name = "batch_code", length = 60)
    private String batchCode;

    @Column(name = "code", nullable = false, unique = true, length = 80)
    private String code;

    @Column(name = "voucher_type", nullable = false, length = 20)
    private String voucherType = "generic";

    @Column(name = "owner_customer_id", length = 100)
    private String ownerCustomerId;

    @Column(name = "issued_by_order_id", length = 100)
    private String issuedByOrderId;

    @Column(name = "single_use", nullable = false)
    private Boolean singleUse = true;

    @Column(name = "max_redemptions", nullable = false)
    private Integer maxRedemptions = 1;

    @Column(name = "redeemed_count", nullable = false)
    private Integer redeemedCount = 0;

    @Column(name = "status", nullable = false, length = 20)
    private String status = "active";

    @Column(name = "valid_from", nullable = false)
    private OffsetDateTime validFrom;

    @Column(name = "valid_to", nullable = false)
    private OffsetDateTime validTo;

    @Column(name = "benefit_outlives_promo", nullable = false)
    private Boolean benefitOutlivesPromo = false;

    @Column(name = "reserved_by_order_id", length = 100)
    private String reservedByOrderId;

    @Column(name = "reserved_until")
    private OffsetDateTime reservedUntil;

    @Column(name = "redeemed_at")
    private OffsetDateTime redeemedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        OffsetDateTime now = OffsetDateTime.now();
        if (createdAt == null) createdAt = now;
        if (validFrom == null) validFrom = now;
    }
}
