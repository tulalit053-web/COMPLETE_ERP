package com.erp.system.repository;

import com.erp.system.entity.PrmTxnRedemption;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface PrmTxnRedemptionRepository extends JpaRepository<PrmTxnRedemption, Long> {
    List<PrmTxnRedemption> findByOrderId(String orderId);
    List<PrmTxnRedemption> findByOrderIdAndStatusIn(String orderId, List<String> statuses);
    Optional<PrmTxnRedemption> findByIdempotencyKey(String idempotencyKey);

    @Query("""
        SELECT r FROM PrmTxnRedemption r
        WHERE r.status = 'reserved'
          AND r.reserveExpiresAt IS NOT NULL
          AND r.reserveExpiresAt < :now
        """)
    List<PrmTxnRedemption> findExpiredReservations(@Param("now") OffsetDateTime now);
}
