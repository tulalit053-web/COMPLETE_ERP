package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.LocalTime;

@Data
@Entity
@Table(name = "prm_mst_promotion_schedule", schema = "schema_promotion")
public class PrmMstPromotionSchedule {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "promotion_id", nullable = false, length = 64)
    private String promotionId;

    @Column(name = "day_of_week", nullable = false, length = 3)
    private String dayOfWeek;

    @Column(name = "time_from", nullable = false)
    private LocalTime timeFrom;

    @Column(name = "time_to", nullable = false)
    private LocalTime timeTo;
}
