package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_txn_return_event", schema = "schema_promotion")
public class PrmTxnReturnEvent {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "company_id")
    private Integer companyId = 1;

    @Column(name = "return_no", nullable = false, unique = true, length = 64)
    private String returnNo;

    @Column(name = "order_id", nullable = false, length = 100)
    private String orderId;

    @Column(name = "return_type", nullable = false, length = 30)
    private String returnType;

    @Column(name = "channel", nullable = false, length = 50)
    private String channel;

    @Column(name = "source_system", nullable = false, length = 50)
    private String sourceSystem = "OMS";

    @Column(name = "reason_code", nullable = false, length = 60)
    private String reasonCode;

    @Column(name = "locale", nullable = false, length = 15)
    private String locale = "id-ID";

    @Column(name = "currency", nullable = false, length = 3)
    private String currency = "IDR";

    @Column(name = "fx_rate_used", nullable = false, precision = 20, scale = 8)
    private BigDecimal fxRateUsed = BigDecimal.ONE;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "returned_lines_json", nullable = false, columnDefinition = "jsonb")
    private String returnedLinesJson;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "recomputed_basket_json", nullable = false, columnDefinition = "jsonb")
    private String recomputedBasketJson;

    @Column(name = "gross_item_value", nullable = false)
    private Long grossItemValue = 0L;

    @Column(name = "promo_adjustment_amount", nullable = false)
    private Long promoAdjustmentAmount = 0L;

    @Column(name = "net_refund_amount", nullable = false)
    private Long netRefundAmount = 0L;

    @Column(name = "external_refund_amount")
    private Long externalRefundAmount;

    @Column(name = "mismatch_flag", nullable = false)
    private Boolean mismatchFlag = false;

    @Column(name = "status", nullable = false, length = 25)
    private String status = "committed";

    @Column(name = "idempotency_key", nullable = false, unique = true, length = 120)
    private String idempotencyKey;

    @Column(name = "returned_at", nullable = false)
    private OffsetDateTime returnedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        OffsetDateTime now = OffsetDateTime.now();
        if (createdAt == null) createdAt = now;
        if (returnedAt == null) returnedAt = now;
    }
}
