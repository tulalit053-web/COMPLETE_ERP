package com.erp.system.repository;

import com.erp.system.entity.PrmMstMessageCatalog;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface PrmMstMessageCatalogRepository extends JpaRepository<PrmMstMessageCatalog, Long> {
    Optional<PrmMstMessageCatalog> findByReasonCodeAndLocale(String reasonCode, String locale);
}
