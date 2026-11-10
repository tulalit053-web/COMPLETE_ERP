package com.erp.system.repository;

import com.erp.system.entity.PrmTxnPromotionBudget;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface PrmTxnPromotionBudgetRepository extends JpaRepository<PrmTxnPromotionBudget, String> {

    /**
     * Reservasi atomik kuota & budget tanpa Redis (mencegah race condition).
     * Mengembalikan 1 jika berhasil, 0 jika kuota atau budget tidak mencukupi.
     */
    @Modifying
    @Query(value = """
        UPDATE schema_promotion.prm_txn_promotion_budget
        SET redemption_reserved = redemption_reserved + 1,
            budget_reserved = budget_reserved + :amountBase,
            updated_at = now()
        WHERE promotion_id = :promoId
          AND (redemption_cap IS NULL OR (redemption_used + redemption_reserved + 1) <= redemption_cap)
          AND (budget_cap IS NULL OR (budget_used + budget_reserved + :amountBase) <= budget_cap)
        """, nativeQuery = true)
    int tryReserveAtomically(@Param("promoId") String promoId, @Param("amountBase") long amountBase);

    /**
     * Konfirmasi reservasi menjadi pemakaian nyata (saat redeem).
     */
    @Modifying
    @Query(value = """
        UPDATE schema_promotion.prm_txn_promotion_budget
        SET redemption_reserved = GREATEST(0, redemption_reserved - 1),
            budget_reserved = GREATEST(0, budget_reserved - :reservedAmountBase),
            redemption_used = redemption_used + 1,
            budget_used = budget_used + :confirmedAmountBase,
            updated_at = now()
        WHERE promotion_id = :promoId
        """, nativeQuery = true)
    int confirmReservationAtomically(
            @Param("promoId") String promoId,
            @Param("reservedAmountBase") long reservedAmountBase,
            @Param("confirmedAmountBase") long confirmedAmountBase);

    /**
     * Redeem langsung (tanpa reservasi sebelumnya) secara atomik.
     */
    @Modifying
    @Query(value = """
        UPDATE schema_promotion.prm_txn_promotion_budget
        SET redemption_used = redemption_used + 1,
            budget_used = budget_used + :amountBase,
            updated_at = now()
        WHERE promotion_id = :promoId
          AND (redemption_cap IS NULL OR (redemption_used + redemption_reserved + 1) <= redemption_cap)
          AND (budget_cap IS NULL OR (budget_used + budget_reserved + :amountBase) <= budget_cap)
        """, nativeQuery = true)
    int tryDirectRedeemAtomically(@Param("promoId") String promoId, @Param("amountBase") long amountBase);

    /**
     * Lepas reservasi yang batal atau lewat TTL.
     */
    @Modifying
    @Query(value = """
        UPDATE schema_promotion.prm_txn_promotion_budget
        SET redemption_reserved = GREATEST(0, redemption_reserved - 1),
            budget_reserved = GREATEST(0, budget_reserved - :amountBase),
            updated_at = now()
        WHERE promotion_id = :promoId
        """, nativeQuery = true)
    int releaseReservationAtomically(@Param("promoId") String promoId, @Param("amountBase") long amountBase);

    /**
     * Kembalikan pemakaian saat rollback / retur penuh (jika net_of_returns = true).
     */
    @Modifying
    @Query(value = """
        UPDATE schema_promotion.prm_txn_promotion_budget
        SET redemption_used = GREATEST(0, redemption_used - :countDelta),
            budget_used = GREATEST(0, budget_used - :amountBase),
            updated_at = now()
        WHERE promotion_id = :promoId
          AND net_of_returns = TRUE
        """, nativeQuery = true)
    int restoreUsedAtomically(
            @Param("promoId") String promoId,
            @Param("countDelta") int countDelta,
            @Param("amountBase") long amountBase);
}
