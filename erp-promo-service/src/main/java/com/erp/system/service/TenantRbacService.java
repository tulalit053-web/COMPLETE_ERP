package com.erp.system.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;

import java.util.*;

@Service
public class TenantRbacService {

    private final JdbcTemplate jdbcTemplate;

    public TenantRbacService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    public String resolveCurrentUsername(String headerOrParamUsername) {
        if (headerOrParamUsername != null && !headerOrParamUsername.isBlank()) {
            return headerOrParamUsername.trim();
        }
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth != null && auth.getPrincipal() instanceof Jwt jwt) {
            String preferred = jwt.getClaimAsString("preferred_username");
            if (preferred != null && !preferred.isBlank()) {
                return preferred;
            }
        }
        return "budi.santoso";
    }

    public Map<String, Object> getUserContext(String requestedUsername, Integer requestedCompanyId) {
        String username = resolveCurrentUsername(requestedUsername);

        // 1. Ambil profil user, role utama, dan company dari schema_admin.adm_mst_user_application
        List<Map<String, Object>> userRows = jdbcTemplate.queryForList("""
            SELECT
                u.dmuapp_id AS user_id,
                u.dmuapp_username AS username,
                u.dmuapp_name AS full_name,
                u.dmuapp_email AS email,
                u.dmuapp_employee_code AS employee_code,
                u.dmuapp_role_id AS role_id,
                u.dmuapp_company_id AS user_company_id,
                u.dmuapp_company AS user_company_code,
                r.dmrole_role_name AS role_name,
                r.dmrole_company_id AS role_company_id,
                c.dmc_company_code AS company_code,
                c.dmc_company_name AS company_name
            FROM schema_admin.adm_mst_user_application u
            LEFT JOIN schema_admin.adm_mst_role r ON r.dmrole_id = u.dmuapp_role_id
            LEFT JOIN schema_admin.adm_mst_company c ON c.dmc_id = u.dmuapp_company_id
            WHERE LOWER(u.dmuapp_username) = LOWER(?)
            LIMIT 1
            """, username);

        Map<String, Object> uRow;
        if (userRows.isEmpty()) {
            uRow = new HashMap<>();
            if ("test_admin".equalsIgnoreCase(username)) {
                uRow.put("user_id", 99);
                uRow.put("username", "test_admin");
                uRow.put("full_name", "Anton (Global Super Admin)");
                uRow.put("email", "tulalit053@gmail.com");
                uRow.put("employee_code", "EMP-000");
                uRow.put("role_id", 1);
                uRow.put("user_company_id", null);
                uRow.put("user_company_code", "GLOBAL");
                uRow.put("role_name", "Super Admin");
                uRow.put("role_company_id", null);
                uRow.put("company_code", "GLOBAL");
                uRow.put("company_name", "Global Holding (Semua Perusahaan)");
            } else {
                uRow.put("user_id", 8);
                uRow.put("username", username);
                uRow.put("full_name", username);
                uRow.put("email", username + "@erp.co.id");
                uRow.put("employee_code", "EMP-001");
                uRow.put("role_id", 1);
                uRow.put("user_company_id", 1);
                uRow.put("user_company_code", "COMP01");
                uRow.put("role_name", "Super Admin");
                uRow.put("role_company_id", null);
                uRow.put("company_code", "COMP01");
                uRow.put("company_name", "PT Maju Jaya");
            }
        } else {
            uRow = userRows.get(0);
        }

        Integer userId = uRow.get("user_id") instanceof Number n ? n.intValue() : 8;
        Integer primaryRoleId = uRow.get("role_id") instanceof Number n ? n.intValue() : 1;
        String roleName = Objects.toString(uRow.get("role_name"), "User");
        Integer roleCompanyId = uRow.get("role_company_id") instanceof Number n ? n.intValue() : null;
        Integer userCompanyId = uRow.get("user_company_id") instanceof Number n ? n.intValue() : null;

        // 1b. Ambil role tambahan dari schema_admin.adm_mst_user_role (jika ada)
        Set<Integer> userRoleIds = new LinkedHashSet<>();
        userRoleIds.add(primaryRoleId);
        List<Map<String, Object>> userRolesList = new ArrayList<>();
        userRolesList.add(Map.of(
                "roleId", primaryRoleId,
                "roleName", roleName,
                "source", "adm_mst_user_application"
        ));

        try {
            List<Map<String, Object>> extraRoles = jdbcTemplate.queryForList("""
                SELECT ur.dmur_role_id AS role_id, r.dmrole_role_name AS role_name
                FROM schema_admin.adm_mst_user_role ur
                JOIN schema_admin.adm_mst_role r ON r.dmrole_id = ur.dmur_role_id
                WHERE ur.dmur_user_id = ? AND COALESCE(ur.dmur_is_active, 1) = 1
                """, userId);
            for (Map<String, Object> er : extraRoles) {
                if (er.get("role_id") instanceof Number n) {
                    int rId = n.intValue();
                    if (userRoleIds.add(rId)) {
                        userRolesList.add(Map.of(
                                "roleId", rId,
                                "roleName", Objects.toString(er.get("role_name"), "Role " + rId),
                                "source", "adm_mst_user_role"
                        ));
                    }
                }
            }
        } catch (Exception ignored) {
        }

        // Global Super Admin = role Super Admin tanpa company (role & user sama-sama NULL).
        // Company Admin (mis. budi.santoso, company_id = 1) memakai role yang sama tapi terikat ke perusahaannya.
        boolean isSuperAdmin = "Super Admin".equalsIgnoreCase(roleName)
                && roleCompanyId == null
                && userCompanyId == null;

        Integer effectiveCompanyId = isSuperAdmin
                ? (requestedCompanyId != null && requestedCompanyId > 0 ? requestedCompanyId : userCompanyId)
                : (userCompanyId != null ? userCompanyId : 1);

        // 2. Daftar perusahaan dari schema_admin.adm_mst_company
        List<Map<String, Object>> companies = jdbcTemplate.queryForList("""
            SELECT dmc_id AS "companyId", dmc_company_code AS "companyCode", dmc_company_name AS "companyName"
            FROM schema_admin.adm_mst_company
            WHERE COALESCE(dmc_is_active, 1) > 0
            ORDER BY dmc_id ASC
            """);

        // 3. Cek Aplikasi & Modul yang dilanggan (Layer 1: adm_mst_company_application & Layer 2: adm_mst_company_module)
        Set<Integer> allowedAppIds = new LinkedHashSet<>();
        Set<Integer> allowedModuleIds = new LinkedHashSet<>();
        List<Map<String, Object>> companySubscriptions = new ArrayList<>();

        Integer checkCompanyId = effectiveCompanyId != null ? effectiveCompanyId : userCompanyId;
        if (isSuperAdmin && checkCompanyId == null) {
            List<Map<String, Object>> allApps = jdbcTemplate.queryForList("""
                SELECT dmap_id, dmap_application_code, dmap_application_name, dmap_description
                FROM schema_admin.adm_mst_application
                WHERE COALESCE(dmap_is_active, true) = true
                ORDER BY dmap_id
                """);
            for (Map<String, Object> a : allApps) {
                int appId = ((Number) a.get("dmap_id")).intValue();
                allowedAppIds.add(appId);
                companySubscriptions.add(Map.of(
                        "applicationId", appId,
                        "applicationCode", Objects.toString(a.get("dmap_application_code"), ""),
                        "applicationName", Objects.toString(a.get("dmap_application_name"), ""),
                        "description", Objects.toString(a.get("dmap_description"), "")
                ));
            }
            jdbcTemplate.queryForList("SELECT dsmd_module_id FROM schema_admin.adm_sec_modules WHERE COALESCE(dsmd_status, 'A') = 'A'")
                    .forEach(r -> allowedModuleIds.add(((Number) r.get("dsmd_module_id")).intValue()));
        } else if (checkCompanyId != null) {
            List<Map<String, Object>> appRows = jdbcTemplate.queryForList("""
                SELECT ca.dmca_application_id, a.dmap_application_code, a.dmap_application_name, a.dmap_description
                FROM schema_admin.adm_mst_company_application ca
                JOIN schema_admin.adm_mst_application a ON a.dmap_id = ca.dmca_application_id
                WHERE ca.dmca_company_id = ?
                  AND COALESCE(ca.dmca_is_active, true) = true
                  AND (ca.dmca_expired_date IS NULL OR ca.dmca_expired_date > CURRENT_TIMESTAMP)
                ORDER BY ca.dmca_application_id
                """, checkCompanyId);
            for (Map<String, Object> r : appRows) {
                if (r.get("dmca_application_id") instanceof Number n) {
                    int appId = n.intValue();
                    allowedAppIds.add(appId);
                    companySubscriptions.add(Map.of(
                            "applicationId", appId,
                            "applicationCode", Objects.toString(r.get("dmap_application_code"), ""),
                            "applicationName", Objects.toString(r.get("dmap_application_name"), ""),
                            "description", Objects.toString(r.get("dmap_description"), "")
                    ));
                }
            }

            List<Map<String, Object>> cmRows = jdbcTemplate.queryForList("""
                SELECT dmcm_module_id, dmcm_is_active
                FROM schema_admin.adm_mst_company_module
                WHERE dmcm_company_id = ?
                """, checkCompanyId);

            if (!cmRows.isEmpty()) {
                for (Map<String, Object> r : cmRows) {
                    Boolean active = (Boolean) r.get("dmcm_is_active");
                    if (Boolean.TRUE.equals(active) && r.get("dmcm_module_id") instanceof Number n) {
                        allowedModuleIds.add(n.intValue());
                    }
                }
            } else if (!allowedAppIds.isEmpty()) {
                List<Map<String, Object>> modRows = jdbcTemplate.queryForList("""
                    SELECT dsmd_module_id, dsmd_application_id
                    FROM schema_admin.adm_sec_modules
                    WHERE COALESCE(dsmd_status, 'A') = 'A'
                    """);
                for (Map<String, Object> r : modRows) {
                    Integer appId = r.get("dsmd_application_id") instanceof Number n ? n.intValue() : null;
                    Integer modId = r.get("dsmd_module_id") instanceof Number n ? n.intValue() : null;
                    if (appId != null && modId != null && allowedAppIds.contains(appId)) {
                        allowedModuleIds.add(modId);
                    }
                }
            }
        }

        boolean promoMenusExist = Optional.ofNullable(jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM schema_admin.adm_mst_menu WHERE dmmenu_code LIKE 'PROMO-%'", Integer.class
        )).orElse(0) > 0;

        // 4. Ambil Menu Hirarki + RoleMenu (adm_mst_role_menu) + UserMenu Override (adm_mst_user_menu)
        List<Map<String, Object>> rawMenus = jdbcTemplate.queryForList("""
            SELECT
                m.dmmenu_id AS menu_id,
                m.dmmenu_parent_menu_id AS parent_menu_id,
                pm.dmmenu_code AS parent_menu_code,
                pm.dmmenu_menu_name AS parent_menu_name,
                m.dmmenu_code AS menu_code,
                m.dmmenu_menu_name AS menu_name,
                m.dmmenu_menu_link AS menu_link,
                m.dmmenu_menu_index AS menu_index,
                m.dmmenu_icon_name AS icon_name,
                m.dmmenu_module_id AS module_id,
                m.dmmenu_show_in_sidemenu AS show_in_sidemenu,
                md.dsmd_module_name AS module_name,
                md.dsmd_application_id AS application_id,
                ap.dmap_application_code AS application_code,
                ap.dmap_application_name AS application_name,
                um.dmum_id AS user_menu_id,
                rm.dmrm_id AS role_menu_id,
                COALESCE(um.dmum_is_view::INT, rm.dmrm_is_view, 0) AS is_view,
                COALESCE(um.dmum_is_add::INT, rm.dmrm_is_add, 0) AS is_add,
                COALESCE(um.dmum_is_edit::INT, rm.dmrm_is_edit, 0) AS is_edit,
                COALESCE(um.dmum_is_delete::INT, rm.dmrm_is_delete, 0) AS is_delete,
                COALESCE(um.dmum_is_approve::INT, rm.dmrm_is_approve, 0) AS is_approve
            FROM schema_admin.adm_mst_menu m
            LEFT JOIN schema_admin.adm_mst_menu pm ON pm.dmmenu_id = m.dmmenu_parent_menu_id
            LEFT JOIN schema_admin.adm_sec_modules md ON md.dsmd_module_id = m.dmmenu_module_id
            LEFT JOIN schema_admin.adm_mst_application ap ON ap.dmap_id = md.dsmd_application_id
            LEFT JOIN schema_admin.adm_mst_role_menu rm
                   ON rm.dmrm_menu_id = m.dmmenu_id AND rm.dmrm_role_id = ?
            LEFT JOIN schema_admin.adm_mst_user_menu um
                   ON um.dmum_menu_id = m.dmmenu_id
                  AND um.dmum_user_id = ?
                  AND (um.dmum_valid_from IS NULL OR um.dmum_valid_from <= CURRENT_DATE)
                  AND (um.dmum_valid_to IS NULL OR um.dmum_valid_to >= CURRENT_DATE)
            WHERE COALESCE(m.dmmenu_is_active, 1) = 1
            ORDER BY COALESCE(md.dsmd_application_id, 99), COALESCE(m.dmmenu_menu_index, 99), m.dmmenu_id
            """, primaryRoleId, userId);

        List<Map<String, Object>> accessibleMenus = new ArrayList<>();
        Map<String, Map<String, Integer>> promoPermissionsByCode = new LinkedHashMap<>();

        for (Map<String, Object> row : rawMenus) {
            Integer appId = row.get("application_id") instanceof Number n ? n.intValue() : null;
            Integer modId = row.get("module_id") instanceof Number n ? n.intValue() : null;
            int isView = row.get("is_view") instanceof Number n ? n.intValue() : 0;
            int isAdd = row.get("is_add") instanceof Number n ? n.intValue() : 0;
            int isEdit = row.get("is_edit") instanceof Number n ? n.intValue() : 0;
            int isDelete = row.get("is_delete") instanceof Number n ? n.intValue() : 0;
            int isApprove = row.get("is_approve") instanceof Number n ? n.intValue() : 0;

            // Fallback untuk Role 3 (CRM User - andi.crm) bila adm_mst_role_menu belum diisi untuk modul CRM (appId = 2)
            if (primaryRoleId == 3 && appId != null && appId == 2 && row.get("role_menu_id") == null) {
                isView = 1;
                isAdd = 1;
                isEdit = 1;
                isDelete = 0;
                isApprove = 0;
            }

            if (!isSuperAdmin) {
                if (appId != null && !allowedAppIds.contains(appId)) continue;
                if (modId != null && !allowedModuleIds.contains(modId)) continue;
                if (isView != 1) continue;
            } else {
                // Jika Super Admin sedang memfilter company tertentu, tampilkan hanya aplikasi milik company tsb
                if (requestedCompanyId != null && requestedCompanyId > 0 && appId != null && !allowedAppIds.contains(appId)) {
                    continue;
                }
                isView = 1;
                isAdd = 1;
                isEdit = 1;
                isDelete = 1;
                isApprove = 1;
            }

            String menuLink = Objects.toString(row.get("menu_link"), null);
            if (menuLink == null || menuLink.isBlank()) continue;

            Map<String, Integer> perms = Map.of(
                    "view", isView,
                    "add", isAdd,
                    "edit", isEdit,
                    "delete", isDelete,
                    "approve", isApprove
            );

            String menuCode = Objects.toString(row.get("menu_code"), "");
            if (menuCode.startsWith("PROMO-")) {
                promoPermissionsByCode.put(menuCode, perms);
            }

            String permSource = row.get("user_menu_id") != null
                    ? "USER_MENU_OVERRIDE"
                    : (isSuperAdmin ? "SUPER_ADMIN_ALL" : "ROLE_MENU");

            Map<String, Object> item = new LinkedHashMap<>();
            item.put("menuId", row.get("menu_id"));
            item.put("parentMenuId", row.get("parent_menu_id"));
            item.put("parentMenuCode", row.get("parent_menu_code"));
            item.put("parentMenuName", Objects.toString(row.get("parent_menu_name"), Objects.toString(row.get("module_name"), "General")));
            item.put("menuCode", menuCode);
            item.put("menuName", row.get("menu_name"));
            item.put("menuLink", menuLink);
            item.put("menuIndex", row.get("menu_index"));
            item.put("iconName", row.get("icon_name"));
            item.put("moduleId", modId);
            item.put("moduleName", Objects.toString(row.get("module_name"), "General"));
            item.put("applicationId", appId);
            item.put("applicationCode", Objects.toString(row.get("application_code"), "APP"));
            item.put("applicationName", Objects.toString(row.get("application_name"), "Application"));
            item.put("permissionSource", permSource);
            item.put("permissions", perms);
            accessibleMenus.add(item);
        }

        // Jika script SQL upgrade schema_admin belum dijalankan oleh user, sediakan default menu PROMO sesuai role & company
        if (!promoMenusExist && (isSuperAdmin || checkCompanyId == null || checkCompanyId == 1 || checkCompanyId == 2)) {
            int canAddEdit = (isSuperAdmin || primaryRoleId == 1 || primaryRoleId == 3 || primaryRoleId == 5 || primaryRoleId == 6 || primaryRoleId == 7) ? 1 : 0;
            int canApprove = (isSuperAdmin || primaryRoleId == 1 || primaryRoleId == 5 || primaryRoleId == 7) ? 1 : 0;
            Map<String, Integer> defaultPerm = Map.of(
                    "view", 1,
                    "add", canAddEdit,
                    "edit", canAddEdit,
                    "delete", canApprove,
                    "approve", canApprove
            );
            String[][] defaultMenus = {
                    {"4001", "PROMO-OVERVIEW", "Ringkasan Promo", "/dashboard/overview", "401", "Promo Overview"},
                    {"4002", "PROMO-LIST", "Daftar Promo", "/dashboard/promos", "402", "Promotion Management"},
                    {"4003", "PROMO-APPROVAL", "Approval Promo", "/dashboard/approvals", "403", "Promo Approvals"},
                    {"4004", "PROMO-SIMULATOR", "Simulator Promo", "/dashboard/simulator", "404", "Rule Simulator"},
                    {"4005", "PROMO-RETURN", "Retur Promo", "/dashboard/returns", "405", "Promo Returns"},
                    {"4006", "PROMO-AUDIT", "Audit Log Promo", "/dashboard/audit", "406", "Promo Audit Log"}
            };
            for (String[] dm : defaultMenus) {
                promoPermissionsByCode.put(dm[1], defaultPerm);
                Map<String, Object> item = new LinkedHashMap<>();
                item.put("menuId", Integer.parseInt(dm[0]));
                item.put("parentMenuId", null);
                item.put("parentMenuCode", "PROMO-HUB");
                item.put("parentMenuName", dm[5]);
                item.put("menuCode", dm[1]);
                item.put("menuName", dm[2]);
                item.put("menuLink", dm[3]);
                item.put("menuIndex", Integer.parseInt(dm[0]) - 4000);
                item.put("iconName", "Tag");
                item.put("moduleId", Integer.parseInt(dm[4]));
                item.put("moduleName", dm[5]);
                item.put("applicationId", 4);
                item.put("applicationCode", "PROMO");
                item.put("applicationName", "Promotion System");
                item.put("permissionSource", "ROLE_MENU");
                item.put("permissions", defaultPerm);
                accessibleMenus.add(item);
            }
            boolean hasPromoSub = companySubscriptions.stream()
                    .anyMatch(s -> "PROMO".equals(s.get("applicationCode")));
            if (!hasPromoSub) {
                companySubscriptions.add(Map.of(
                        "applicationId", 4,
                        "applicationCode", "PROMO",
                        "applicationName", "Promotion System",
                        "description", "Config-Driven Promo & Discount Governance Engine"
                ));
            }
        }

        // Daftar user di schema_admin untuk pengujian multi-user
        List<Map<String, Object>> availableUsers = jdbcTemplate.queryForList("""
            SELECT
                u.dmuapp_username AS username,
                u.dmuapp_name AS name,
                u.dmuapp_company_id AS "companyId",
                COALESCE(c.dmc_company_name, 'Global (All Companies)') AS "companyName",
                COALESCE(r.dmrole_role_name, 'User') AS "roleName"
            FROM schema_admin.adm_mst_user_application u
            LEFT JOIN schema_admin.adm_mst_company c ON c.dmc_id = u.dmuapp_company_id
            LEFT JOIN schema_admin.adm_mst_role r ON r.dmrole_id = u.dmuapp_role_id
            WHERE COALESCE(u.dmuapp_is_active, 1) = 1
            ORDER BY u.dmuapp_id ASC
            """);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("userId", userId);
        result.put("username", uRow.get("username"));
        result.put("fullName", uRow.get("full_name"));
        result.put("email", Objects.toString(uRow.get("email"), uRow.get("username") + "@erp.co.id"));
        result.put("employeeCode", Objects.toString(uRow.get("employee_code"), "EMP-" + userId));
        result.put("roleId", primaryRoleId);
        result.put("roleName", roleName);
        result.put("userRoles", userRolesList);
        result.put("isSuperAdmin", isSuperAdmin);
        result.put("userCompanyId", userCompanyId);
        result.put("effectiveCompanyId", effectiveCompanyId);
        result.put("companyCode", Objects.toString(uRow.get("company_code"), Objects.toString(uRow.get("user_company_code"), "GLOBAL")));
        result.put("companyName", Objects.toString(uRow.get("company_name"), isSuperAdmin ? "Global Multi-Company" : "PT Maju Jaya"));
        result.put("companySubscriptions", companySubscriptions);
        result.put("menus", accessibleMenus);
        result.put("promoPermissions", promoPermissionsByCode);
        result.put("companies", companies);
        result.put("availableUsers", availableUsers);
        return result;
    }

    @SuppressWarnings("unchecked")
    public void verifyPromoPermission(String requestedUsername, Integer requestedCompanyId, String menuCode, String action) {
        Map<String, Object> ctx = getUserContext(requestedUsername, requestedCompanyId);
        boolean isSuperAdmin = Boolean.TRUE.equals(ctx.get("isSuperAdmin"));
        if (isSuperAdmin) {
            return;
        }
        Map<String, Map<String, Integer>> promoPerms =
                (Map<String, Map<String, Integer>>) ctx.getOrDefault("promoPermissions", Map.of());
        Map<String, Integer> perm = promoPerms.get(menuCode);
        if (perm == null) {
            throw new SecurityException("Akses ditolak: Perusahaan atau Role Anda tidak memiliki akses ke menu " + menuCode);
        }
        Integer flag = perm.getOrDefault(action.toLowerCase(), 0);
        if (flag == null || flag != 1) {
            throw new SecurityException("Akses ditolak: Role '" + ctx.get("roleName")
                    + "' tidak memiliki hak '" + action.toUpperCase() + "' pada menu " + menuCode);
        }
    }
}
