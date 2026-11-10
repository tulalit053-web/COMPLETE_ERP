package com.erp.system.entity;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serializable;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class PrmTxnRedemptionCounterId implements Serializable {
    private String promotionId;
    private String subjectType;
    private String subjectKey;
}
