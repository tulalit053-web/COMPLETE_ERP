package com.erp.system.repository;

import com.erp.system.entity.PrmMstPromotionTranslation;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface PrmMstPromotionTranslationRepository extends JpaRepository<PrmMstPromotionTranslation, Long> {
    List<PrmMstPromotionTranslation> findByPromotionIdAndVersion(String promotionId, Integer version);
    List<PrmMstPromotionTranslation> findByPromotionId(String promotionId);
    Optional<PrmMstPromotionTranslation> findByPromotionIdAndVersionAndLocale(String promotionId, Integer version, String locale);
}
