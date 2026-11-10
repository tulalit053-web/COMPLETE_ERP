package com.erp.system.repository;

import com.erp.system.entity.PrmLogAudit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PrmLogAuditRepository extends JpaRepository<PrmLogAudit, Long> {
    List<PrmLogAudit> findTop100ByOrderByCreatedAtDesc();
    List<PrmLogAudit> findByEntityTypeAndEntityIdOrderByCreatedAtDesc(String entityType, String entityId);
}
