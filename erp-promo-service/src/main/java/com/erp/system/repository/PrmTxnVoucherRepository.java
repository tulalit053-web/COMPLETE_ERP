package com.erp.system.repository;

import com.erp.system.entity.PrmTxnVoucher;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface PrmTxnVoucherRepository extends JpaRepository<PrmTxnVoucher, Long> {
    Optional<PrmTxnVoucher> findByCodeIgnoreCase(String code);
    List<PrmTxnVoucher> findByPromotionId(String promotionId);
    List<PrmTxnVoucher> findByOwnerCustomerIdAndStatus(String ownerCustomerId, String status);
}
