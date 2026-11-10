package com.erp.system.repository;

import com.erp.system.entity.PrmMstPromotionVersion;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface PrmMstPromotionVersionRepository extends JpaRepository<PrmMstPromotionVersion, Long> {
    List<PrmMstPromotionVersion> findByPromotionIdOrderByVersionDesc(String promotionId);
    Optional<PrmMstPromotionVersion> findByPromotionIdAndVersion(String promotionId, Integer version);
}
