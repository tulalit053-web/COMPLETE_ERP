package com.erp.system.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.LocalDate;

@Data
@Entity
@Table(name = "prm_mst_bin_list_entry", schema = "schema_promotion")
public class PrmMstBinListEntry {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "list_id", nullable = false, length = 60)
    private String listId;

    @Column(name = "bin_prefix", nullable = false, length = 12)
    private String binPrefix;

    @Column(name = "bank", nullable = false, length = 100)
    private String bank;

    @Column(name = "card_type", nullable = false, length = 20)
    private String cardType;

    @Column(name = "card_network", nullable = false, length = 30)
    private String cardNetwork;

    @Column(name = "valid_from")
    private LocalDate validFrom;

    @Column(name = "valid_to")
    private LocalDate validTo;
}
