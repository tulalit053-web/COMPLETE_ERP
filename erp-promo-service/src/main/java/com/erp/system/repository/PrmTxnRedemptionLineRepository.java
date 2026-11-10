package com.erp.system.repository;

import com.erp.system.entity.PrmTxnRedemptionLine;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PrmTxnRedemptionLineRepository extends JpaRepository<PrmTxnRedemptionLine, Long> {
    List<PrmTxnRedemptionLine> findByOrderId(String orderId);
    List<PrmTxnRedemptionLine> findByRedemptionId(Long redemptionId);
}
