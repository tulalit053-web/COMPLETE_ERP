package com.erp.system.controller;

import com.erp.system.dto.GovernanceActionRequest;
import com.erp.system.dto.PromoAdminDto;
import com.erp.system.dto.PromoEvaluateRequest;
import com.erp.system.dto.PromoEvaluateResponse;
import com.erp.system.service.DashboardReferenceService;
import com.erp.system.service.PromoAdminGovernanceService;
import com.erp.system.service.PromoEngineService;
import com.erp.system.service.TenantRbacService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
public class PromoAdminController {

    private final PromoAdminGovernanceService adminGovernanceService;
    private final DashboardReferenceService dashboardReferenceService;
    private final PromoEngineService promoEngineService;
    private final TenantRbacService tenantRbacService;

    public PromoAdminController(
            PromoAdminGovernanceService adminGovernanceService,
            DashboardReferenceService dashboardReferenceService,
            PromoEngineService promoEngineService,
            TenantRbacService tenantRbacService) {
        this.adminGovernanceService = adminGovernanceService;
        this.dashboardReferenceService = dashboardReferenceService;
        this.promoEngineService = promoEngineService;
        this.tenantRbacService = tenantRbacService;
    }

    @GetMapping("/v1/me/context")
    public ResponseEntity<Map<String, Object>> getUserMultiTenantContext(
            @RequestHeader(value = "X-User-Name", required = false) String headerUser,
            @RequestParam(value = "username", required = false) String paramUser,
            @RequestParam(value = "companyId", required = false) Integer companyId) {
        String user = paramUser != null && !paramUser.isBlank() ? paramUser : headerUser;
        return ResponseEntity.ok(tenantRbacService.getUserContext(user, companyId));
    }

    @GetMapping("/v1/dashboard/overview")
    public ResponseEntity<Map<String, Object>> getDashboardOverview(
            @RequestHeader(value = "X-User-Name", required = false) String headerUser,
            @RequestParam(value = "username", required = false) String paramUser,
            @RequestParam(value = "companyId", required = false) Integer companyId) {
        String user = paramUser != null && !paramUser.isBlank() ? paramUser : headerUser;
        return ResponseEntity.ok(dashboardReferenceService.getDashboardOverview(user, companyId));
    }

    @GetMapping("/v1/reference/metadata")
    public ResponseEntity<Map<String, Object>> getMetadataReferences() {
        return ResponseEntity.ok(dashboardReferenceService.getAllMetadataReferences());
    }

    @GetMapping("/v1/admin/promos")
    public ResponseEntity<List<PromoAdminDto>> listPromotions(
            @RequestHeader(value = "X-User-Name", required = false) String headerUser,
            @RequestParam(value = "username", required = false) String paramUser,
            @RequestParam(value = "companyId", required = false) Integer companyId) {
        String user = paramUser != null && !paramUser.isBlank() ? paramUser : headerUser;
        Map<String, Object> ctx = tenantRbacService.getUserContext(user, companyId);
        Integer effectiveCompanyId = (Integer) ctx.get("effectiveCompanyId");
        return ResponseEntity.ok(adminGovernanceService.listPromotionsByCompany(effectiveCompanyId));
    }

    @GetMapping("/v1/admin/promos/{id}")
    public ResponseEntity<PromoAdminDto> getPromotion(@PathVariable("id") String id) {
        return ResponseEntity.ok(adminGovernanceService.getPromotionDetail(id));
    }

    @PostMapping("/v1/admin/promos")
    public ResponseEntity<PromoAdminDto> createPromotion(
            @RequestHeader(value = "X-User-Name", required = false) String headerUser,
            @RequestParam(value = "username", required = false) String paramUser,
            @RequestParam(value = "companyId", required = false) Integer companyId,
            @RequestBody PromoAdminDto dto) {
        String user = paramUser != null && !paramUser.isBlank() ? paramUser : headerUser;
        tenantRbacService.verifyPromoPermission(user, companyId, "PROMO-LIST", "ADD");
        Map<String, Object> ctx = tenantRbacService.getUserContext(user, companyId);
        Integer effectiveCompanyId = (Integer) ctx.get("effectiveCompanyId");
        if (effectiveCompanyId != null && effectiveCompanyId > 0) {
            dto.setCompanyId(effectiveCompanyId);
            dto.setCompanyCode(String.valueOf(ctx.getOrDefault("companyCode", "COMP0" + effectiveCompanyId)));
        }
        if (dto.getMakerId() == null || dto.getMakerId().isBlank()) {
            dto.setMakerId(String.valueOf(ctx.getOrDefault("fullName", "Maker")));
        }
        return ResponseEntity.ok(adminGovernanceService.createOrUpdatePromotion(dto));
    }

    @PutMapping("/v1/admin/promos/{id}")
    public ResponseEntity<PromoAdminDto> updatePromotion(
            @RequestHeader(value = "X-User-Name", required = false) String headerUser,
            @PathVariable("id") String id,
            @RequestBody PromoAdminDto dto) {
        tenantRbacService.verifyPromoPermission(headerUser, dto.getCompanyId(), "PROMO-LIST", "EDIT");
        dto.setId(id);
        return ResponseEntity.ok(adminGovernanceService.createOrUpdatePromotion(dto));
    }

    @PostMapping("/v1/admin/promos/{id}/submit")
    public ResponseEntity<PromoAdminDto> submitPromotion(
            @RequestHeader(value = "X-User-Name", required = false) String headerUser,
            @PathVariable("id") String id,
            @RequestBody(required = false) GovernanceActionRequest req) {
        tenantRbacService.verifyPromoPermission(headerUser, null, "PROMO-LIST", "EDIT");
        return ResponseEntity.ok(adminGovernanceService.submitForApproval(
                id, req != null ? req : new GovernanceActionRequest()));
    }

    @PostMapping("/v1/admin/promos/{id}/approve")
    public ResponseEntity<PromoAdminDto> approvePromotion(
            @RequestHeader(value = "X-User-Name", required = false) String headerUser,
            @PathVariable("id") String id,
            @RequestBody(required = false) GovernanceActionRequest req) {
        tenantRbacService.verifyPromoPermission(headerUser, null, "PROMO-APPROVAL", "APPROVE");
        return ResponseEntity.ok(adminGovernanceService.approvePromotion(
                id, req != null ? req : new GovernanceActionRequest()));
    }

    @PostMapping("/v1/admin/promos/{id}/reject")
    public ResponseEntity<PromoAdminDto> rejectPromotion(
            @RequestHeader(value = "X-User-Name", required = false) String headerUser,
            @PathVariable("id") String id,
            @RequestBody GovernanceActionRequest req) {
        tenantRbacService.verifyPromoPermission(headerUser, null, "PROMO-APPROVAL", "APPROVE");
        return ResponseEntity.ok(adminGovernanceService.rejectPromotion(id, req));
    }

    @PostMapping("/v1/admin/promos/{id}/extend")
    public ResponseEntity<PromoAdminDto> extendExpiredDate(
            @RequestHeader(value = "X-User-Name", required = false) String headerUser,
            @PathVariable("id") String id,
            @RequestBody GovernanceActionRequest req) {
        tenantRbacService.verifyPromoPermission(headerUser, null, "PROMO-LIST", "EDIT");
        return ResponseEntity.ok(adminGovernanceService.extendExpiredDate(id, req));
    }

    @PostMapping("/v1/admin/promos/{id}/pause")
    public ResponseEntity<PromoAdminDto> togglePause(
            @RequestHeader(value = "X-User-Name", required = false) String headerUser,
            @PathVariable("id") String id,
            @RequestBody(required = false) GovernanceActionRequest req) {
        tenantRbacService.verifyPromoPermission(headerUser, null, "PROMO-LIST", "EDIT");
        return ResponseEntity.ok(adminGovernanceService.togglePause(
                id, req != null ? req : new GovernanceActionRequest()));
    }

    @PostMapping("/v1/admin/promos/{id}/simulate")
    public ResponseEntity<PromoEvaluateResponse> simulatePromotion(
            @PathVariable("id") String id,
            @RequestBody PromoEvaluateRequest req) {
        return ResponseEntity.ok(promoEngineService.simulateSinglePromo(id, req));
    }

    @GetMapping("/v1/admin/approvals/pending")
    public ResponseEntity<List<PromoAdminDto>> listPendingApprovals(
            @RequestHeader(value = "X-User-Name", required = false) String headerUser,
            @RequestParam(value = "companyId", required = false) Integer companyId) {
        Map<String, Object> ctx = tenantRbacService.getUserContext(headerUser, companyId);
        Integer effectiveCompanyId = (Integer) ctx.get("effectiveCompanyId");
        return ResponseEntity.ok(adminGovernanceService.listPromotionsByCompany(effectiveCompanyId).stream()
                .filter(p -> "pending".equals(p.getStatus()))
                .toList());
    }
}
