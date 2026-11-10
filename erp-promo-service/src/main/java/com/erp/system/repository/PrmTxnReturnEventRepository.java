package com.erp.system.repository;

import com.erp.system.entity.PrmTxnReturnEvent;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface PrmTxnReturnEventRepository extends JpaRepository<PrmTxnReturnEvent, Long> {
    List<PrmTxnReturnEvent> findTop100ByOrderByReturnedAtDesc();
    List<PrmTxnReturnEvent> findByOrderIdOrderByReturnedAtAsc(String orderId);
    Optional<PrmTxnReturnEvent> findByIdempotencyKey(String idempotencyKey);
}
