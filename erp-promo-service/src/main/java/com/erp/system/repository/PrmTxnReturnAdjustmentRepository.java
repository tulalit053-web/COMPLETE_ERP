package com.erp.system.repository;

import com.erp.system.entity.PrmTxnReturnAdjustment;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PrmTxnReturnAdjustmentRepository extends JpaRepository<PrmTxnReturnAdjustment, Long> {
    List<PrmTxnReturnAdjustment> findByReturnEventId(Long returnEventId);
    List<PrmTxnReturnAdjustment> findByPromotionIdOrderByCreatedAtDesc(String promotionId);
}
