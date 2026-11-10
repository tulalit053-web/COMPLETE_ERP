package com.erp.system.repository;

import com.erp.system.entity.PrmMstStackingRule;
import com.erp.system.entity.PrmMstStackingRuleId;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface PrmMstStackingRuleRepository extends JpaRepository<PrmMstStackingRule, PrmMstStackingRuleId> {
}
