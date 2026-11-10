package com.erp.system.repository;

import com.erp.system.entity.PrmMstChannel;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PrmMstChannelRepository extends JpaRepository<PrmMstChannel, String> {
    List<PrmMstChannel> findByIsActiveTrue();
}
