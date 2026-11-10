package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_txn_tradein_request", schema = "schema_promotion")
public class PrmTxnTradeinRequest {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "tradein_no", nullable = false, unique = true, length = 64)
    private String tradeinNo;

    @Column(name = "promotion_id", length = 64)
    private String promotionId;

    @Column(name = "order_id", length = 100)
    private String orderId;

    @Column(name = "customer_id", nullable = false, length = 100)
    private String customerId;

    @Column(name = "mode", nullable = false, length = 25)
    private String mode = "trade_in";

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "device_json", nullable = false, columnDefinition = "jsonb")
    private String deviceJson;

    @Column(name = "claimed_grade", nullable = false, length = 1)
    private String claimedGrade;

    @Column(name = "inspected_grade", length = 1)
    private String inspectedGrade;

    @Column(name = "currency", nullable = false, length = 3)
    private String currency = "IDR";

    @Column(name = "appraised_value", nullable = false)
    private Long appraisedValue;

    @Column(name = "bonus_amount", nullable = false)
    private Long bonusAmount = 0L;

    @Column(name = "final_credit_amount")
    private Long finalCreditAmount;

    @Column(name = "requires_inspection", nullable = false)
    private Boolean requiresInspection = true;

    @Column(name = "status", nullable = false, length = 25)
    private String status = "appraised";

    @Column(name = "price_lock_until")
    private OffsetDateTime priceLockUntil;

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
