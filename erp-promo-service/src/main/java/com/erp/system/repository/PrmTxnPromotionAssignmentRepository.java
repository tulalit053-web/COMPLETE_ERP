package com.erp.system.repository;

import com.erp.system.entity.PrmTxnPromotionAssignment;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PrmTxnPromotionAssignmentRepository extends JpaRepository<PrmTxnPromotionAssignment, String> {
    List<PrmTxnPromotionAssignment> findByCustomerIdAndStatus(String customerId, String status);
    List<PrmTxnPromotionAssignment> findByPromotionId(String promotionId);
}
