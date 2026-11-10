package com.erp.system.repository;

import com.erp.system.entity.PrmTxnIdempotency;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface PrmTxnIdempotencyRepository extends JpaRepository<PrmTxnIdempotency, String> {
}
