package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;

@Data
@Entity
@Table(name = "prm_txn_redemption_line", schema = "schema_promotion")
public class PrmTxnRedemptionLine {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "redemption_id", nullable = false)
    private Long redemptionId;

    @Column(name = "order_id", nullable = false, length = 100)
    private String orderId;

    @Column(name = "order_line_id", nullable = false, length = 80)
    private String orderLineId;

    @Column(name = "promotion_id", nullable = false, length = 64)
    private String promotionId;

    @Column(name = "promotion_version", nullable = false)
    private Integer promotionVersion;

    @Column(name = "sku", nullable = false, length = 80)
    private String sku;

    @Column(name = "qty", nullable = false)
    private Integer qty;

    @Column(name = "returned_qty", nullable = false)
    private Integer returnedQty = 0;

    @Column(name = "currency", nullable = false, length = 3)
    private String currency = "IDR";

    @Column(name = "unit_list_price", nullable = false)
    private Long unitListPrice;

    @Column(name = "line_gross_amount", nullable = false)
    private Long lineGrossAmount;

    @Column(name = "discount_amount", nullable = false)
    private Long discountAmount = 0L;

    @Column(name = "line_net_amount", nullable = false)
    private Long lineNetAmount;

    @Column(name = "is_free_item", nullable = false)
    private Boolean isFreeItem = false;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "allocated_funding_json", nullable = false, columnDefinition = "jsonb")
    private String allocatedFundingJson = "[]";

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = OffsetDateTime.now();
    }
}
