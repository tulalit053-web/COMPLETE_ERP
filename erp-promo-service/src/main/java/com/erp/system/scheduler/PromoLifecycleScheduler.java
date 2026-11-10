package com.erp.system.scheduler;

import com.erp.system.entity.PrmMstPromotion;
import com.erp.system.entity.PrmTxnRedemption;
import com.erp.system.repository.PrmMstPromotionRepository;
import com.erp.system.repository.PrmTxnPromotionBudgetRepository;
import com.erp.system.repository.PrmTxnRedemptionRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;

@Component
public class PromoLifecycleScheduler {

    private static final Logger log = LoggerFactory.getLogger(PromoLifecycleScheduler.class);

    private final PrmMstPromotionRepository promotionRepository;
    private final PrmTxnRedemptionRepository redemptionRepository;
    private final PrmTxnPromotionBudgetRepository budgetRepository;

    public PromoLifecycleScheduler(
            PrmMstPromotionRepository promotionRepository,
            PrmTxnRedemptionRepository redemptionRepository,
            PrmTxnPromotionBudgetRepository budgetRepository) {
        this.promotionRepository = promotionRepository;
        this.redemptionRepository = redemptionRepository;
        this.budgetRepository = budgetRepository;
    }

    /**
     * Berjalan setiap 60 detik:
     * 1. Mengubah promo 'scheduled' -> 'active' saat start_at tiba.
     * 2. Mengubah promo 'active/scheduled/paused' -> 'expired' saat melewati end_at / expires_at.
     * 3. Melepas kuota reservasi checkout yang sudah melewati reserve_expires_at (TTL).
     */
    @Scheduled(fixedDelay = 60_000)
    @Transactional
    public void runLifecycleHousekeeping() {
        OffsetDateTime now = OffsetDateTime.now();

        List<PrmMstPromotion> toActivate = promotionRepository.findScheduledReadyToActivate(now);
        for (PrmMstPromotion p : toActivate) {
            p.setStatus("active");
            promotionRepository.save(p);
            log.info(">>> [PROMO-SCHEDULER] Promo {} otomatis menjadi ACTIVE", p.getId());
        }

        List<PrmMstPromotion> toExpire = promotionRepository.findPromotionsReadyToExpire(now);
        for (PrmMstPromotion p : toExpire) {
            p.setStatus("expired");
            promotionRepository.save(p);
            log.info(">>> [PROMO-SCHEDULER] Promo {} otomatis menjadi EXPIRED", p.getId());
        }

        List<PrmTxnRedemption> expiredReservations = redemptionRepository.findExpiredReservations(now);
        for (PrmTxnRedemption r : expiredReservations) {
            budgetRepository.releaseReservationAtomically(r.getPromotionId(), r.getDiscountAmountBase());
            r.setStatus("expired");
            redemptionRepository.save(r);
            log.info(">>> [PROMO-SCHEDULER] Reservasi {} melewati TTL, kuota dikembalikan", r.getRedemptionNo());
        }
    }
}
