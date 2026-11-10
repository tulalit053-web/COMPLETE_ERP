package com.erp.system.repository;

import com.erp.system.entity.PrmMstAudience;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface PrmMstAudienceRepository extends JpaRepository<PrmMstAudience, String> {
}
