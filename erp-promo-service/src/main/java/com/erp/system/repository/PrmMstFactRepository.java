package com.erp.system.repository;

import com.erp.system.entity.PrmMstFact;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PrmMstFactRepository extends JpaRepository<PrmMstFact, String> {
    List<PrmMstFact> findByIsActiveTrueOrderByFactGroupAscFactKeyAsc();
}
