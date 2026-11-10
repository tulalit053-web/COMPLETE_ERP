package com.erp.system.repository;

import com.erp.system.entity.PrmMstPromotion;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface PrmMstPromotionRepository extends JpaRepository<PrmMstPromotion, String> {

    Optional<PrmMstPromotion> findByCompanyIdAndCode(Integer companyId, String code);

    List<PrmMstPromotion> findByStatusOrderByPriorityDescEndAtAscIdAsc(String status);

    @Query("""
        SELECT p FROM PrmMstPromotion p
        WHERE p.status = 'active'
          AND p.startAt <= :now
          AND p.endAt >= :now
          AND p.expiresAt >= :now
        ORDER BY p.priority DESC, p.endAt ASC, p.id ASC
        """)
    List<PrmMstPromotion> findCandidateActivePromotions(@Param("now") OffsetDateTime now);

    @Query("""
        SELECT p FROM PrmMstPromotion p
        WHERE p.status = 'scheduled'
          AND p.startAt <= :now
          AND p.endAt > :now
          AND p.expiresAt > :now
        """)
    List<PrmMstPromotion> findScheduledReadyToActivate(@Param("now") OffsetDateTime now);

    @Query("""
        SELECT p FROM PrmMstPromotion p
        WHERE p.status IN ('active', 'scheduled', 'paused')
          AND (p.expiresAt < :now OR p.endAt < :now)
        """)
    List<PrmMstPromotion> findPromotionsReadyToExpire(@Param("now") OffsetDateTime now);
}
