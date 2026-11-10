package com.erp.system.repository;

import com.erp.system.entity.PrmMstBinListEntry;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PrmMstBinListEntryRepository extends JpaRepository<PrmMstBinListEntry, Long> {
    List<PrmMstBinListEntry> findByListId(String listId);
}
