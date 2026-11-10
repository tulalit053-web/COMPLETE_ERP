package com.erp.system.repository;

import com.erp.system.entity.PrmMstApprovalMatrix;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PrmMstApprovalMatrixRepository extends JpaRepository<PrmMstApprovalMatrix, Long> {
    List<PrmMstApprovalMatrix> findByCompanyIdAndIsActiveTrueOrderByPriorityDesc(Integer companyId);
}
