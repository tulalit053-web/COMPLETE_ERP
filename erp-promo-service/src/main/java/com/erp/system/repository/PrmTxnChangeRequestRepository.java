package com.erp.system.repository;

import com.erp.system.entity.PrmTxnChangeRequest;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface PrmTxnChangeRequestRepository extends JpaRepository<PrmTxnChangeRequest, Long> {
    List<PrmTxnChangeRequest> findByStatusOrderBySubmittedAtDesc(String status);
    List<PrmTxnChangeRequest> findByPromotionIdOrderBySubmittedAtDesc(String promotionId);
    Optional<PrmTxnChangeRequest> findFirstByPromotionIdAndStatusOrderBySubmittedAtDesc(String promotionId, String status);
}
