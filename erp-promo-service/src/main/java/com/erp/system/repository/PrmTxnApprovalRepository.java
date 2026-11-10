package com.erp.system.repository;

import com.erp.system.entity.PrmTxnApproval;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PrmTxnApprovalRepository extends JpaRepository<PrmTxnApproval, Long> {
    List<PrmTxnApproval> findByChangeRequestIdOrderByLevelAsc(Long changeRequestId);
    List<PrmTxnApproval> findByPromotionIdOrderByDecidedAtDesc(String promotionId);
    boolean existsByChangeRequestIdAndApproverId(Long changeRequestId, String approverId);
}
