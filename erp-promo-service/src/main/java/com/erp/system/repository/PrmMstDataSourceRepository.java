package com.erp.system.repository;

import com.erp.system.entity.PrmMstDataSource;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PrmMstDataSourceRepository extends JpaRepository<PrmMstDataSource, String> {
    List<PrmMstDataSource> findByIsActiveTrueOrderByDomainAscPriorityAsc();
}
