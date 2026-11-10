package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;

@Data
@Entity
@Table(name = "prm_mst_promotion_scope_item", schema = "schema_promotion")
public class PrmMstPromotionScopeItem {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "promotion_id", nullable = false, length = 64)
    private String promotionId;

    @Column(name = "ref_type", nullable = false, length = 20)
    private String refType;

    @Column(name = "ref_value", nullable = false, length = 120)
    private String refValue;

    @Column(name = "is_exclude", nullable = false)
    private Boolean isExclude = false;
}
