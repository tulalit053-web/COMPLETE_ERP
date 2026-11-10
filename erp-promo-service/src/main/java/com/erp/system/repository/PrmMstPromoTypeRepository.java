package com.erp.system.repository;

import com.erp.system.entity.PrmMstPromoType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PrmMstPromoTypeRepository extends JpaRepository<PrmMstPromoType, String> {
    List<PrmMstPromoType> findByIsActiveTrueOrderByPhaseAscTypeCodeAsc();
}
