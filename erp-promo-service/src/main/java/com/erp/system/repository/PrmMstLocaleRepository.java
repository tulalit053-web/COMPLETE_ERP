package com.erp.system.repository;

import com.erp.system.entity.PrmMstLocale;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PrmMstLocaleRepository extends JpaRepository<PrmMstLocale, String> {
    List<PrmMstLocale> findByIsActiveTrue();
}
