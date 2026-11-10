package com.erp.system.repository;

import com.erp.system.entity.PrmMstBenefitKind;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PrmMstBenefitKindRepository extends JpaRepository<PrmMstBenefitKind, String> {
    List<PrmMstBenefitKind> findByIsActiveTrueOrderByPhaseAscKindAsc();
}
