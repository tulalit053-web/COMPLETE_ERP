package com.erp.system.repository;

import com.erp.system.entity.PrmMstCurrency;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PrmMstCurrencyRepository extends JpaRepository<PrmMstCurrency, String> {
    List<PrmMstCurrency> findByIsActiveTrue();
}
