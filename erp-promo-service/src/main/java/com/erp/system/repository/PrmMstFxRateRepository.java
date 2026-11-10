package com.erp.system.repository;

import com.erp.system.entity.PrmMstFxRate;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface PrmMstFxRateRepository extends JpaRepository<PrmMstFxRate, Long> {
    Optional<PrmMstFxRate> findFirstByBaseCurrencyAndQuoteCurrencyOrderByEffectiveAtDesc(String baseCurrency, String quoteCurrency);
}
