package com.erp.system.service;

import com.erp.system.dto.GovernanceActionRequest;
import com.erp.system.dto.PromoAdminDto;
import com.erp.system.entity.*;
import com.erp.system.repository.*;
import com.erp.system.util.ConfigHashUtil;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.*;

@Service
public class PromoAdminGovernanceService {

    private final PrmMstPromotionRepository promotionRepository;
    private final PrmMstPromotionVersionRepository versionRepository;
    private final PrmMstPromotionTranslationRepository translationRepository;
    private final PrmTxnPromotionBudgetRepository budgetRepository;
    private final PrmTxnChangeRequestRepository changeRequestRepository;
    private final PrmTxnApprovalRepository approvalRepository;
    private final PrmLogAuditRepository auditRepository;
    private final ObjectMapper objectMapper;

    public PromoAdminGovernanceService(
            PrmMstPromotionRepository promotionRepository,
            PrmMstPromotionVersionRepository versionRepository,
            PrmMstPromotionTranslationRepository translationRepository,
            PrmTxnPromotionBudgetRepository budgetRepository,
            PrmTxnChangeRequestRepository changeRequestRepository,
            PrmTxnApprovalRepository approvalRepository,
            PrmLogAuditRepository auditRepository,
            ObjectMapper objectMapper) {
        this.promotionRepository = promotionRepository;
        this.versionRepository = versionRepository;
        this.translationRepository = translationRepository;
        this.budgetRepository = budgetRepository;
        this.changeRequestRepository = changeRequestRepository;
        this.approvalRepository = approvalRepository;
        this.auditRepository = auditRepository;
        this.objectMapper = objectMapper;
    }

    public List<PromoAdminDto> listAllPromotions() {
        return listPromotionsByCompany(null);
    }

    public List<PromoAdminDto> listPromotionsByCompany(Integer companyId) {
        List<PrmMstPromotion> promos = promotionRepository.findAll();
        if (companyId != null && companyId > 0) {
            promos = promos.stream()
                    .filter(p -> companyId.equals(Optional.ofNullable(p.getCompanyId()).orElse(1)))
                    .collect(java.util.stream.Collectors.toList());
        }
        promos.sort(Comparator.comparing(PrmMstPromotion::getId));
        return promos.stream().map(this::toAdminDto).toList();
    }

    public PromoAdminDto getPromotionDetail(String id) {
        PrmMstPromotion promo = promotionRepository.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("Promotion not found: " + id));
        return toAdminDto(promo);
    }

    @Transactional
    public PromoAdminDto createOrUpdatePromotion(PromoAdminDto dto) {
        boolean isNew = dto.getId() == null || !promotionRepository.existsById(dto.getId());
        PrmMstPromotion promo = isNew ? new PrmMstPromotion() : promotionRepository.findById(dto.getId()).orElseThrow();

        if (isNew) {
            promo.setId(Optional.ofNullable(dto.getId()).orElse("P-" + (100 + promotionRepository.count() + 1)));
            promo.setVersion(1);
            promo.setStatus("draft");
            promo.setApprovalStatus("draft");
        } else {
            promo.setVersion(promo.getVersion() + 1);
            // Aturan keras #2: Mengubah promo setelah approval membatalkan approval dan kembali ke draft
            promo.setStatus("draft");
            promo.setApprovalStatus("draft");
        }

        promo.setCompanyId(Optional.ofNullable(dto.getCompanyId()).orElse(1));
        promo.setCompanyCode(Optional.ofNullable(dto.getCompanyCode()).orElse("COMP0" + promo.getCompanyId()));
        promo.setCode(Optional.ofNullable(dto.getCode()).orElse(promo.getId()));
        promo.setName(dto.getName());
        promo.setDescription(dto.getDescription());
        promo.setType(Optional.ofNullable(dto.getType()).orElse("discount_percent"));
        promo.setPriority(Optional.ofNullable(dto.getPriority()).orElse(100));
        promo.setStartAt(Optional.ofNullable(dto.getStartAt()).orElse(OffsetDateTime.now()));
        promo.setEndAt(Optional.ofNullable(dto.getEndAt()).orElse(OffsetDateTime.now().plusDays(30)));
        promo.setExpiresAt(Optional.ofNullable(dto.getExpiresAt()).orElse(promo.getEndAt()));

        if (promo.getStartAt().isAfter(promo.getEndAt()) || promo.getEndAt().isAfter(promo.getExpiresAt())) {
            throw new IllegalArgumentException("Invalid schedule: start_at <= end_at <= expires_at is required");
        }

        promo.setBaseCurrency(Optional.ofNullable(dto.getBaseCurrency()).orElse("IDR"));
        promo.setSupportedCurrencies(Optional.ofNullable(dto.getSupportedCurrencies()).orElse(List.of("IDR", "USD")));
        promo.setDefaultLocale(Optional.ofNullable(dto.getDefaultLocale()).orElse("id-ID"));
        promo.setRequiredLocales(Optional.ofNullable(dto.getRequiredLocales()).orElse(List.of("id-ID", "en-US")));
        promo.setMakerId(Optional.ofNullable(dto.getMakerId()).orElse("Rina"));
        promo.setMakerAt(OffsetDateTime.now());

        String configStr = toJson(Optional.ofNullable(dto.getConfig()).orElse(Map.of()));
        String hash = ConfigHashUtil.sha256(configStr);
        promo.setConfigJson(configStr);
        promo.setConfigHash(hash);

        PrmMstPromotion saved = promotionRepository.save(promo);

        // Simpan snapshot versi
        PrmMstPromotionVersion ver = new PrmMstPromotionVersion();
        ver.setPromotionId(saved.getId());
        ver.setVersion(saved.getVersion());
        ver.setConfigJson(configStr);
        ver.setConfigHash(hash);
        ver.setStartAt(saved.getStartAt());
        ver.setEndAt(saved.getEndAt());
        ver.setExpiresAt(saved.getExpiresAt());
        ver.setApprovalStatus(saved.getApprovalStatus());
        ver.setChangedBy(saved.getMakerId());
        versionRepository.save(ver);

        // Simpan budget
        PrmTxnPromotionBudget budget = budgetRepository.findById(saved.getId()).orElseGet(() -> {
            PrmTxnPromotionBudget b = new PrmTxnPromotionBudget();
            b.setPromotionId(saved.getId());
            return b;
        });
        budget.setCurrency(saved.getBaseCurrency());
        if (dto.getBudgetCap() != null) budget.setBudgetCap(dto.getBudgetCap());
        if (dto.getRedemptionCap() != null) budget.setRedemptionCap(dto.getRedemptionCap());
        budgetRepository.save(budget);

        logAudit("PROMOTION", saved.getId(), isNew ? "created" : "updated", saved.getMakerId(), "maker", null);
        return toAdminDto(saved);
    }

    @Transactional
    public PromoAdminDto submitForApproval(String promoId, GovernanceActionRequest req) {
        PrmMstPromotion promo = promotionRepository.findById(promoId).orElseThrow();
        String maker = Optional.ofNullable(req.getActor()).orElse(promo.getMakerId());

        promo.setStatus("pending_approval");
        promo.setApprovalStatus("pending");
        promo.setMakerId(maker);
        promotionRepository.save(promo);

        PrmTxnChangeRequest cr = new PrmTxnChangeRequest();
        cr.setRequestNo("CR-" + promo.getId() + "-V" + promo.getVersion() + "-" + (System.currentTimeMillis() % 10000));
        cr.setEntityType("PROMOTION");
        cr.setPromotionId(promo.getId());
        cr.setFromVersion(promo.getApprovedVersion());
        cr.setToVersion(promo.getVersion());
        cr.setConfigHash(promo.getConfigHash());
        cr.setPayloadJson(promo.getConfigJson());
        cr.setRequiredLevels((short) 1);
        cr.setCurrentLevel((short) 1);
        cr.setStatus("pending");
        cr.setMakerId(maker);
        cr.setMakerNote(req.getNote());
        changeRequestRepository.save(cr);

        logAudit("PROMOTION", promo.getId(), "submitted", maker, "maker", req.getNote());
        return toAdminDto(promo);
    }

    @Transactional
    public PromoAdminDto approvePromotion(String promoId, GovernanceActionRequest req) {
        PrmMstPromotion promo = promotionRepository.findById(promoId).orElseThrow();
        String checker = Optional.ofNullable(req.getActor()).orElse("Dodi");

        // Aturan keras #1: Maker != Checker
        if (checker.equalsIgnoreCase(promo.getMakerId())) {
            throw new IllegalStateException("Maker cannot approve their own promotion (maker=" + promo.getMakerId() + ")");
        }

        PrmTxnChangeRequest cr = changeRequestRepository
                .findFirstByPromotionIdAndStatusOrderBySubmittedAtDesc(promoId, "pending")
                .orElseGet(() -> {
                    PrmTxnChangeRequest fallback = new PrmTxnChangeRequest();
                    fallback.setRequestNo("CR-" + promoId + "-" + (System.currentTimeMillis() % 10000));
                    fallback.setEntityType("PROMOTION");
                    fallback.setPromotionId(promoId);
                    fallback.setToVersion(promo.getVersion());
                    fallback.setConfigHash(promo.getConfigHash());
                    fallback.setPayloadJson(promo.getConfigJson());
                    fallback.setMakerId(promo.getMakerId());
                    fallback.setStatus("pending");
                    return changeRequestRepository.save(fallback);
                });

        PrmTxnApproval approval = new PrmTxnApproval();
        approval.setChangeRequestId(cr.getId());
        approval.setPromotionId(promoId);
        approval.setLevel((short) 1);
        approval.setRequiredRole("PROMO_CHECKER_L1");
        approval.setMakerId(promo.getMakerId());
        approval.setApproverId(checker);
        approval.setDecision("approved");
        approval.setNote(Optional.ofNullable(req.getNote()).orElse("Approved"));
        approval.setConfigHash(promo.getConfigHash());
        approvalRepository.save(approval);

        cr.setStatus("approved");
        cr.setCompletedAt(OffsetDateTime.now());
        changeRequestRepository.save(cr);

        promo.setApprovalStatus("approved");
        promo.setApprovedVersion(promo.getVersion());
        promo.setApprovedConfigHash(promo.getConfigHash());
        promo.setStatus(promo.getStartAt().isAfter(OffsetDateTime.now()) ? "scheduled" : "active");
        promotionRepository.save(promo);

        logAudit("PROMOTION", promoId, "approved", checker, "checker", req.getNote());
        return toAdminDto(promo);
    }

    @Transactional
    public PromoAdminDto rejectPromotion(String promoId, GovernanceActionRequest req) {
        PrmMstPromotion promo = promotionRepository.findById(promoId).orElseThrow();
        String checker = Optional.ofNullable(req.getActor()).orElse("Dodi");
        if (req.getNote() == null || req.getNote().isBlank()) {
            throw new IllegalArgumentException("Reason note is required when rejecting a promotion");
        }
        if (checker.equalsIgnoreCase(promo.getMakerId())) {
            throw new IllegalStateException("Maker cannot review their own promotion");
        }

        changeRequestRepository.findFirstByPromotionIdAndStatusOrderBySubmittedAtDesc(promoId, "pending")
                .ifPresent(cr -> {
                    PrmTxnApproval approval = new PrmTxnApproval();
                    approval.setChangeRequestId(cr.getId());
                    approval.setPromotionId(promoId);
                    approval.setLevel((short) 1);
                    approval.setRequiredRole("PROMO_CHECKER_L1");
                    approval.setMakerId(promo.getMakerId());
                    approval.setApproverId(checker);
                    approval.setDecision("rejected");
                    approval.setNote(req.getNote());
                    approval.setConfigHash(promo.getConfigHash());
                    approvalRepository.save(approval);

                    cr.setStatus("rejected");
                    cr.setCompletedAt(OffsetDateTime.now());
                    changeRequestRepository.save(cr);
                });

        promo.setStatus("rejected");
        promo.setApprovalStatus("rejected");
        promotionRepository.save(promo);

        logAudit("PROMOTION", promoId, "rejected", checker, "checker", req.getNote());
        return toAdminDto(promo);
    }

    @Transactional
    public PromoAdminDto extendExpiredDate(String promoId, GovernanceActionRequest req) {
        PrmMstPromotion promo = promotionRepository.findById(promoId).orElseThrow();
        if (req.getNote() == null || req.getNote().isBlank()) {
            throw new IllegalArgumentException("Reason is required to extend expired date");
        }
        if (req.getNewExpiresAt() == null || req.getNewExpiresAt().isBlank()) {
            throw new IllegalArgumentException("newExpiresAt is required");
        }

        OffsetDateTime newExp = parseFlexibleDate(req.getNewExpiresAt());
        long diffDays = ChronoUnit.DAYS.between(promo.getExpiresAt().toLocalDate(), newExp.toLocalDate());
        if (diffDays <= 0 || diffDays > 90) {
            throw new IllegalArgumentException("New expired date must move forward between 1 and 90 days");
        }

        promo.setEndAt(newExp);
        promo.setExpiresAt(newExp);
        if ("expired".equals(promo.getStatus())) {
            promo.setStatus("active");
        }
        promotionRepository.save(promo);

        String actor = Optional.ofNullable(req.getActor()).orElse("Dodi");
        logAudit("PROMOTION", promoId, "extended", actor, "checker",
                "→ " + newExp.toLocalDate() + " · " + req.getNote());
        return toAdminDto(promo);
    }

    @Transactional
    public PromoAdminDto togglePause(String promoId, GovernanceActionRequest req) {
        PrmMstPromotion promo = promotionRepository.findById(promoId).orElseThrow();
        String nextStatus = "paused".equals(promo.getStatus()) ? "active" : "paused";
        promo.setStatus(nextStatus);
        promotionRepository.save(promo);
        logAudit("PROMOTION", promoId, nextStatus, Optional.ofNullable(req.getActor()).orElse("Ops"), "ops", req.getNote());
        return toAdminDto(promo);
    }

    private void logAudit(String entityType, String entityId, String action, String actor, String role, String reason) {
        PrmLogAudit audit = new PrmLogAudit();
        audit.setEntityType(entityType);
        audit.setEntityId(entityId);
        audit.setAction(action);
        audit.setActor(actor);
        audit.setActorRole(role);
        audit.setReason(reason);
        auditRepository.save(audit);
    }

    @SuppressWarnings("unchecked")
    public PromoAdminDto toAdminDto(PrmMstPromotion p) {
        PrmTxnPromotionBudget b = budgetRepository.findById(p.getId()).orElse(null);
        List<PrmMstPromotionTranslation> translations = translationRepository.findByPromotionId(p.getId());
        Map<String, String> localizedNames = new LinkedHashMap<>();
        localizedNames.put("id", p.getName());
        localizedNames.put("en", p.getName());
        for (PrmMstPromotionTranslation tr : translations) {
            if (tr.getLocale().startsWith("id")) localizedNames.put("id", tr.getName());
            if (tr.getLocale().startsWith("en")) localizedNames.put("en", tr.getName());
        }

        Map<String, Object> cfg = parseJsonMap(p.getConfigJson());
        double roi = cfg.get("roi") instanceof Number n ? n.doubleValue() : 0.0;
        double rr = cfg.get("return_rate") instanceof Number n ? n.doubleValue() : 0.0;

        List<PrmLogAudit> audits = auditRepository.findByEntityTypeAndEntityIdOrderByCreatedAtDesc("PROMOTION", p.getId());
        List<Map<String, Object>> history = new ArrayList<>();
        String checkerId = null;
        for (int i = audits.size() - 1; i >= 0; i--) {
            PrmLogAudit a = audits.get(i);
            if ("approved".equals(a.getAction())) checkerId = a.getActor();
            Map<String, Object> item = new LinkedHashMap<>();
            item.put("date", a.getCreatedAt().toLocalDate().toString());
            item.put("actor", a.getActor());
            item.put("action", a.getAction());
            if (a.getReason() != null) item.put("note", a.getReason());
            history.add(item);
        }

        long daysUntilExpiry = ChronoUnit.DAYS.between(LocalDate.now(), p.getExpiresAt().toLocalDate());

        return PromoAdminDto.builder()
                .id(p.getId())
                .companyId(p.getCompanyId())
                .companyCode(p.getCompanyCode())
                .code(p.getCode())
                .name(p.getName())
                .localizedNames(localizedNames)
                .description(p.getDescription())
                .type(p.getType())
                .status("pending_approval".equals(p.getStatus()) ? "pending" : p.getStatus())
                .priority(p.getPriority())
                .version(p.getVersion())
                .startAt(p.getStartAt())
                .endAt(p.getEndAt())
                .expiresAt(p.getExpiresAt())
                .daysUntilExpiry(daysUntilExpiry)
                .baseCurrency(p.getBaseCurrency())
                .supportedCurrencies(p.getSupportedCurrencies())
                .defaultLocale(p.getDefaultLocale())
                .requiredLocales(p.getRequiredLocales())
                .makerId(p.getMakerId())
                .checkerId(checkerId)
                .approvalStatus(p.getApprovalStatus())
                .approvedVersion(p.getApprovedVersion())
                .budgetCap(b != null && b.getBudgetCap() != null ? b.getBudgetCap() : 0L)
                .budgetUsed(b != null ? b.getBudgetUsed() : 0L)
                .budgetReserved(b != null ? b.getBudgetReserved() : 0L)
                .redemptionCap(b != null && b.getRedemptionCap() != null ? b.getRedemptionCap() : 0)
                .redemptionUsed(b != null ? b.getRedemptionUsed() : 0)
                .returnRate(rr)
                .roi(roi)
                .config(cfg)
                .history(history)
                .build();
    }

    private OffsetDateTime parseFlexibleDate(String input) {
        try {
            return OffsetDateTime.parse(input);
        } catch (Exception e) {
            LocalDate ld = LocalDate.parse(input.substring(0, 10));
            return ld.atTime(23, 59, 59).atOffset(ZoneOffset.ofHours(7));
        }
    }

    private Map<String, Object> parseJsonMap(String json) {
        if (json == null || json.isBlank()) return Map.of();
        try {
            return objectMapper.readValue(json, new TypeReference<>() {});
        } catch (Exception e) {
            return Map.of();
        }
    }

    private String toJson(Object obj) {
        try {
            return objectMapper.writeValueAsString(obj);
        } catch (Exception e) {
            return "{}";
        }
    }
}
