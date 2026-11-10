package com.erp.system.entity;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serializable;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class PrmMstStackingRuleId implements Serializable {
    private String groupA;
    private String groupB;
}
