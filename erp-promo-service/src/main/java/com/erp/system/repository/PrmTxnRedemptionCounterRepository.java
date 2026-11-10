package com.erp.system.repository;

import com.erp.system.entity.PrmTxnRedemptionCounter;
import com.erp.system.entity.PrmTxnRedemptionCounterId;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface PrmTxnRedemptionCounterRepository extends JpaRepository<PrmTxnRedemptionCounter, PrmTxnRedemptionCounterId> {
}
