package com.erp.system.repository;

import com.erp.system.entity.PrmMstPromotionScopeItem;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PrmMstPromotionScopeItemRepository extends JpaRepository<PrmMstPromotionScopeItem, Long> {
    List<PrmMstPromotionScopeItem> findByPromotionId(String promotionId);
    void deleteByPromotionId(String promotionId);
}
