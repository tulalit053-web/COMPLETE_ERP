package com.erp.system.dto;

import lombok.Data;

@Data
public class GovernanceActionRequest {
    private String actor;
    private String role;
    private String note;
    private String newExpiresAt;
}
