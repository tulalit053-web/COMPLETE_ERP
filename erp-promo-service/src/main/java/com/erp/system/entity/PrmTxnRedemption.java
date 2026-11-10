package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_txn_redemption", schema = "schema_promotion")
public class PrmTxnRedemption {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "redemption_no", nullable = false, unique = true, length = 64)
    private String redemptionNo;

    @Column(name = "promotion_id", nullable = false, length = 64)
    private String promotionId;

    @Column(name = "promotion_version", nullable = false)
    private Integer promotionVersion;

    @Column(name = "voucher_id")
    private Long voucherId;

    @Column(name = "order_id", nullable = false, length = 100)
    private String orderId;

    @Column(name = "customer_id", length = 100)
    private String customerId;

    @Column(name = "channel", nullable = false, length = 50)
    private String channel;

    @Column(name = "sub_channel", length = 80)
    private String subChannel;

    @Column(name = "store_id", length = 80)
    private String storeId;

    @Column(name = "locale", nullable = false, length = 15)
    private String locale = "id-ID";

    @Column(name = "currency", nullable = false, length = 3)
    private String currency = "IDR";

    @Column(name = "fx_rate_to_base", nullable = false, precision = 20, scale = 8)
    private BigDecimal fxRateToBase = BigDecimal.ONE;

    @Column(name = "discount_amount", nullable = false)
    private Long discountAmount = 0L;

    @Column(name = "discount_amount_base", nullable = false)
    private Long discountAmountBase = 0L;

    @Column(name = "shipping_subsidy_amount", nullable = false)
    private Long shippingSubsidyAmount = 0L;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "benefit_snapshot_json", nullable = false, columnDefinition = "jsonb")
    private String benefitSnapshotJson;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "funding_snapshot_json", nullable = false, columnDefinition = "jsonb")
    private String fundingSnapshotJson;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "input_snapshot_json", nullable = false, columnDefinition = "jsonb")
    private String inputSnapshotJson;

    @Column(name = "status", nullable = false, length = 20)
    private String status = "reserved";

    @Column(name = "reserve_expires_at")
    private OffsetDateTime reserveExpiresAt;

    @Column(name = "confirmed_at")
    private OffsetDateTime confirmedAt;

    @Column(name = "reversed_at")
    private OffsetDateTime reversedAt;

    @Column(name = "idempotency_key", nullable = false, unique = true, length = 120)
    private String idempotencyKey;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        OffsetDateTime now = OffsetDateTime.now();
        if (createdAt == null) createdAt = now;
        if (updatedAt == null) updatedAt = now;
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = OffsetDateTime.now();
    }
}
