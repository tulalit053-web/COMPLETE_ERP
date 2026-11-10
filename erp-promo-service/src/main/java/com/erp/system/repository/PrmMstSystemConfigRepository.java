package com.erp.system.repository;

import com.erp.system.entity.PrmMstSystemConfig;
import com.erp.system.entity.PrmMstSystemConfigId;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface PrmMstSystemConfigRepository extends JpaRepository<PrmMstSystemConfig, PrmMstSystemConfigId> {
}
