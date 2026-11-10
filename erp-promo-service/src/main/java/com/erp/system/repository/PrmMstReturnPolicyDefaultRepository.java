package com.erp.system.repository;

import com.erp.system.entity.PrmMstReturnPolicyDefault;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface PrmMstReturnPolicyDefaultRepository extends JpaRepository<PrmMstReturnPolicyDefault, Long> {
    Optional<PrmMstReturnPolicyDefault> findByPromoCategory(String promoCategory);
}
