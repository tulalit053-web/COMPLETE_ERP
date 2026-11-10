package com.erp.system.service;

import com.erp.system.dto.PromoEvaluateRequest;
import com.erp.system.dto.PromoEvaluateResponse;
import com.erp.system.entity.*;
import com.erp.system.repository.*;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Service;

import java.time.OffsetDateTime;
import java.util.*;
import java.util.stream.Collectors;

@Service
public class PromoEngineService {

    private final PrmMstPromotionRepository promotionRepository;
    private final PrmTxnPromotionBudgetRepository budgetRepository;
    private final PrmMstMessageCatalogRepository messageCatalogRepository;
    private final PrmTxnVoucherRepository voucherRepository;
    private final ObjectMapper objectMapper;

    public PromoEngineService(
            PrmMstPromotionRepository promotionRepository,
            PrmTxnPromotionBudgetRepository budgetRepository,
            PrmMstMessageCatalogRepository messageCatalogRepository,
            PrmTxnVoucherRepository voucherRepository,
            ObjectMapper objectMapper) {
        this.promotionRepository = promotionRepository;
        this.budgetRepository = budgetRepository;
        this.messageCatalogRepository = messageCatalogRepository;
        this.voucherRepository = voucherRepository;
        this.objectMapper = objectMapper;
    }

    public PromoEvaluateResponse evaluate(PromoEvaluateRequest req) {
        OffsetDateTime now = parseTimeOrNow(req.getContext().getNow());
        List<PrmMstPromotion> candidates = promotionRepository.findCandidateActivePromotions(now);
        return evaluateAgainstPromotions(req, candidates);
    }

    public PromoEvaluateResponse simulateSinglePromo(String promoId, PromoEvaluateRequest req) {
        PrmMstPromotion promo = promotionRepository.findById(promoId)
                .orElseThrow(() -> new IllegalArgumentException("Promotion not found: " + promoId));
        return evaluateAgainstPromotions(req, List.of(promo));
    }

    @SuppressWarnings("unchecked")
    public PromoEvaluateResponse evaluateAgainstPromotions(PromoEvaluateRequest req, List<PrmMstPromotion> candidates) {
        String locale = Optional.ofNullable(req.getContext().getLocale()).orElse("id-ID");
        String currency = Optional.ofNullable(req.getContext().getCurrency()).orElse("IDR");
        String channel = Optional.ofNullable(req.getContext().getChannel()).orElse("web");

        List<PromoEvaluateRequest.CartItemInput> items = Optional.ofNullable(req.getCart().getItems()).orElse(List.of());
        long subtotal = items.stream()
                .mapToLong(i -> (long) Optional.ofNullable(i.getQty()).orElse(1) * Optional.ofNullable(i.getUnitPrice()).orElse(0L))
                .sum();
        int totalQty = items.stream().mapToInt(i -> Optional.ofNullable(i.getQty()).orElse(1)).sum();
        long shippingOriginal = Optional.ofNullable(req.getCart().getShippingFee()).orElse(0L);

        List<PromoEvaluateResponse.RejectedPromo> rejected = new ArrayList<>();
        List<CandidateResult> eligibleResults = new ArrayList<>();

        Map<String, PrmTxnPromotionBudget> budgetMap = budgetRepository.findAllById(
                candidates.stream().map(PrmMstPromotion::getId).toList()
        ).stream().collect(Collectors.toMap(PrmTxnPromotionBudget::getPromotionId, b -> b));

        for (PrmMstPromotion promo : candidates) {
            Map<String, Object> cfg = parseJsonMap(promo.getConfigJson());

            // 1. Cek Scope Channel
            Map<String, Object> scope = (Map<String, Object>) cfg.getOrDefault("scope", Map.of());
            List<String> channels = (List<String>) scope.getOrDefault("channels", List.of());
            if (!channels.isEmpty() && !channels.contains(channel)) {
                rejected.add(buildRejected(promo, "CHANNEL_NOT_ELIGIBLE", locale, Map.of("channel", channel)));
                continue;
            }

            // 2. Cek Kuota & Budget
            PrmTxnPromotionBudget budget = budgetMap.get(promo.getId());
            if (budget != null) {
                if (budget.getRedemptionCap() != null &&
                        (budget.getRedemptionUsed() + budget.getRedemptionReserved()) >= budget.getRedemptionCap()) {
                    rejected.add(buildRejected(promo, "QUOTA_EXHAUSTED", locale, Map.of()));
                    continue;
                }
                if (budget.getBudgetCap() != null &&
                        (budget.getBudgetUsed() + budget.getBudgetReserved()) >= budget.getBudgetCap()) {
                    rejected.add(buildRejected(promo, "BUDGET_EXHAUSTED", locale, Map.of()));
                    continue;
                }
            }

            // 3. Filter eligible items dalam scope
            List<PromoEvaluateRequest.CartItemInput> eligibleItems = filterEligibleItems(items, scope);
            long eligibleSubtotal = eligibleItems.stream()
                    .mapToLong(i -> (long) Optional.ofNullable(i.getQty()).orElse(1) * Optional.ofNullable(i.getUnitPrice()).orElse(0L))
                    .sum();
            int eligibleQty = eligibleItems.stream()
                    .mapToInt(i -> Optional.ofNullable(i.getQty()).orElse(1))
                    .sum();

            // 4. Evaluasi Conditions
            Map<String, Object> facts = buildFactMap(req, subtotal, eligibleSubtotal, totalQty, eligibleQty, items);
            Map<String, Object> conditions = (Map<String, Object>) cfg.get("conditions");
            ConditionOutcome condOutcome = evaluateConditionNode(conditions, facts);
            if (!condOutcome.passed) {
                rejected.add(buildRejected(promo, condOutcome.reasonCode, locale, condOutcome.detail));
                continue;
            }

            // 5. Hitung Benefit
            Map<String, Object> benefit = (Map<String, Object>) cfg.getOrDefault("benefit", Map.of());
            Map<String, Object> limits = (Map<String, Object>) cfg.getOrDefault("limits", Map.of());
            Map<String, Object> stacking = (Map<String, Object>) cfg.getOrDefault("stacking", Map.of());
            List<Map<String, Object>> funding = (List<Map<String, Object>>) cfg.getOrDefault("funding",
                    List.of(Map.of("party", "Merchant", "share_percent", 100)));

            String group = Optional.ofNullable((String) stacking.get("group")).orElse(resolveDefaultGroup(promo.getType()));
            String stackingMode = Optional.ofNullable((String) stacking.get("mode")).orElse("exclusive_in_group");

            BenefitCalculation calc = calculateBenefit(promo, benefit, limits, eligibleItems, subtotal, eligibleSubtotal, shippingOriginal, req);
            if (calc.discountAmount <= 0 && calc.reward == null) {
                continue;
            }

            eligibleResults.add(new CandidateResult(promo, group, stackingMode, calc, funding));
        }

        // 6. Resolusi Stacking & Prioritas per Group (best_of / priority tertinggi menang)
        Map<String, List<CandidateResult>> byGroup = eligibleResults.stream()
                .collect(Collectors.groupingBy(r -> r.group, LinkedHashMap::new, Collectors.toList()));

        List<CandidateResult> winners = new ArrayList<>();
        for (Map.Entry<String, List<CandidateResult>> entry : byGroup.entrySet()) {
            String grp = entry.getKey();
            List<CandidateResult> groupList = entry.getValue();
            if ("reward".equalsIgnoreCase(grp)) {
                winners.addAll(groupList);
                continue;
            }
            groupList.sort(Comparator
                    .comparingLong((CandidateResult r) -> r.calc.discountAmount).reversed()
                    .thenComparing(Comparator.comparingInt((CandidateResult r) -> r.promo.getPriority()).reversed())
                    .thenComparing(r -> r.promo.getEndAt())
                    .thenComparing(r -> r.promo.getId()));

            CandidateResult best = groupList.get(0);
            winners.add(best);
            for (int i = 1; i < groupList.size(); i++) {
                CandidateResult loser = groupList.get(i);
                rejected.add(buildRejected(loser.promo, "LOSES_TO_HIGHER_PRIORITY", locale, Map.of("winner", best.promo.getId())));
            }
        }

        // 7. Susun Urutan Pricing Pipeline & Alokasi Diskon per Baris Item
        long itemDiscountTotal = 0L;
        long cartDiscountTotal = 0L;
        long tradeinCredit = 0L;
        long shippingDiscount = 0L;
        long paymentDiscount = 0L;

        List<PromoEvaluateResponse.AppliedPromo> applied = new ArrayList<>();
        List<PromoEvaluateResponse.RewardEarned> rewards = new ArrayList<>();

        for (CandidateResult w : winners) {
            if (w.calc.reward != null) {
                rewards.add(w.calc.reward);
            }
            if (w.calc.discountAmount > 0) {
                switch (w.group) {
                    case "item_discount" -> itemDiscountTotal += w.calc.discountAmount;
                    case "cart_discount" -> cartDiscountTotal += w.calc.discountAmount;
                    case "tradein" -> tradeinCredit += w.calc.discountAmount;
                    case "shipping" -> shippingDiscount += Math.min(shippingOriginal - shippingDiscount, w.calc.discountAmount);
                    case "payment" -> paymentDiscount += w.calc.discountAmount;
                    default -> cartDiscountTotal += w.calc.discountAmount;
                }
                applied.add(PromoEvaluateResponse.AppliedPromo.builder()
                        .promoId(w.promo.getId())
                        .code(w.promo.getCode())
                        .name(w.promo.getName())
                        .type(w.promo.getType())
                        .group(w.group)
                        .version(w.promo.getVersion())
                        .discount(w.calc.discountAmount)
                        .target(w.calc.target)
                        .funding(w.funding)
                        .build());
            }
        }

        long totalGoodsDiscount = Math.min(subtotal, itemDiscountTotal + cartDiscountTotal + tradeinCredit + paymentDiscount);
        long shippingNet = Math.max(0L, shippingOriginal - shippingDiscount);
        long discountTotal = totalGoodsDiscount + shippingDiscount;
        long grandTotal = Math.max(0L, (subtotal - totalGoodsDiscount) + shippingNet);

        // Alokasi proporsional diskon barang ke setiap baris item (Bagian 10 & 13.1)
        List<PromoEvaluateResponse.LineBreakdown> lineBreakdowns = allocateDiscountToLines(
                items, subtotal, totalGoodsDiscount, applied.isEmpty() ? null : applied.get(0).getPromoId());

        return PromoEvaluateResponse.builder()
                .applied(applied)
                .rejected(rejected)
                .lineBreakdowns(lineBreakdowns)
                .rewards(rewards)
                .currency(currency)
                .locale(locale)
                .totals(PromoEvaluateResponse.Totals.builder()
                        .subtotal(subtotal)
                        .itemDiscountTotal(itemDiscountTotal)
                        .cartDiscountTotal(cartDiscountTotal)
                        .tradeinCredit(tradeinCredit)
                        .shippingFeeOriginal(shippingOriginal)
                        .shippingDiscount(shippingDiscount)
                        .shippingNet(shippingNet)
                        .paymentDiscount(paymentDiscount)
                        .discountTotal(discountTotal)
                        .grandTotal(grandTotal)
                        .build())
                .build();
    }

    private List<PromoEvaluateResponse.LineBreakdown> allocateDiscountToLines(
            List<PromoEvaluateRequest.CartItemInput> items,
            long subtotal,
            long totalGoodsDiscount,
            String primaryPromoId) {
        List<PromoEvaluateResponse.LineBreakdown> lines = new ArrayList<>();
        if (items.isEmpty()) return lines;

        long allocatedSum = 0L;
        int largestIdx = 0;
        long largestGross = -1L;

        for (int i = 0; i < items.size(); i++) {
            PromoEvaluateRequest.CartItemInput item = items.get(i);
            int qty = Optional.ofNullable(item.getQty()).orElse(1);
            long unitPrice = Optional.ofNullable(item.getUnitPrice()).orElse(0L);
            long gross = qty * unitPrice;
            if (gross > largestGross) {
                largestGross = gross;
                largestIdx = i;
            }
            long lineDiscount = subtotal > 0 ? (totalGoodsDiscount * gross) / subtotal : 0L;
            allocatedSum += lineDiscount;

            lines.add(PromoEvaluateResponse.LineBreakdown.builder()
                    .lineId(Optional.ofNullable(item.getLineId()).orElse("L" + (i + 1)))
                    .sku(item.getSku())
                    .qty(qty)
                    .unitListPrice(unitPrice)
                    .lineGrossAmount(gross)
                    .discountAmount(lineDiscount)
                    .lineNetAmount(Math.max(0L, gross - lineDiscount))
                    .appliedPromoId(primaryPromoId)
                    .build());
        }

        // Sisa pembulatan diberikan ke item bernilai terbesar (Bagian 10)
        long remainder = totalGoodsDiscount - allocatedSum;
        if (remainder != 0 && !lines.isEmpty()) {
            PromoEvaluateResponse.LineBreakdown target = lines.get(largestIdx);
            long adjustedDiscount = Math.min(target.getLineGrossAmount(), target.getDiscountAmount() + remainder);
            target.setDiscountAmount(adjustedDiscount);
            target.setLineNetAmount(Math.max(0L, target.getLineGrossAmount() - adjustedDiscount));
        }
        return lines;
    }

    @SuppressWarnings("unchecked")
    private BenefitCalculation calculateBenefit(
            PrmMstPromotion promo,
            Map<String, Object> benefit,
            Map<String, Object> limits,
            List<PromoEvaluateRequest.CartItemInput> eligibleItems,
            long subtotal,
            long eligibleSubtotal,
            long shippingOriginal,
            PromoEvaluateRequest req) {

        String kind = Optional.ofNullable((String) benefit.get("kind")).orElse(promo.getType());
        Map<String, Object> params = (Map<String, Object>) benefit.getOrDefault("params", Map.of());
        String applyTo = Optional.ofNullable((String) params.get("apply_to")).orElse("cart");
        long baseAmount = "item".equalsIgnoreCase(applyTo) ? eligibleSubtotal : subtotal;

        long discount = 0L;
        String target = applyTo;
        PromoEvaluateResponse.RewardEarned reward = null;

        switch (kind) {
            case "discount_percent" -> {
                double pct = toDouble(params.getOrDefault("percent", 0));
                discount = Math.round(baseAmount * (pct / 100.0));
                long maxAmt = toLong(params.get("max_amount"));
                if (maxAmt > 0) discount = Math.min(discount, maxAmt);
            }
            case "discount_fixed" -> {
                discount = Math.min(baseAmount, toLong(params.get("amount")));
            }
            case "fixed_price" -> {
                long fixedPrice = toLong(params.get("price"));
                long diff = 0L;
                for (PromoEvaluateRequest.CartItemInput item : eligibleItems) {
                    long u = Optional.ofNullable(item.getUnitPrice()).orElse(0L);
                    int q = Optional.ofNullable(item.getQty()).orElse(1);
                    if (u > fixedPrice) {
                        diff += (u - fixedPrice) * q;
                    }
                }
                discount = diff;
                target = "item";
            }
            case "buy_x_get_y" -> {
                int buyQty = (int) toLong(params.getOrDefault("buy_qty", 1));
                int getQty = (int) toLong(params.getOrDefault("get_qty", 1));
                double getDiscPct = toDouble(params.getOrDefault("get_discount_percent", 100));
                boolean repeat = Boolean.TRUE.equals(params.getOrDefault("repeat", true));
                int maxRepeat = (int) toLong(params.getOrDefault("max_repeat", 5));

                List<Long> unitPrices = new ArrayList<>();
                for (PromoEvaluateRequest.CartItemInput item : eligibleItems) {
                    int q = Optional.ofNullable(item.getQty()).orElse(1);
                    long u = Optional.ofNullable(item.getUnitPrice()).orElse(0L);
                    for (int k = 0; k < q; k++) unitPrices.add(u);
                }
                Collections.sort(unitPrices); // lowest_price first
                int groupSize = buyQty + getQty;
                int sets = groupSize > 0 ? unitPrices.size() / groupSize : 0;
                if (!repeat && sets > 1) sets = 1;
                if (maxRepeat > 0) sets = Math.min(sets, maxRepeat);

                int freeUnits = sets * getQty;
                long bxgyDisc = 0L;
                for (int i = 0; i < freeUnits && i < unitPrices.size(); i++) {
                    bxgyDisc += Math.round(unitPrices.get(i) * (getDiscPct / 100.0));
                }
                discount = bxgyDisc;
                target = "item";
            }
            case "tiered_discount" -> {
                String basis = Optional.ofNullable((String) params.get("tier_basis")).orElse("qty");
                long metric = "amount".equalsIgnoreCase(basis) ? eligibleSubtotal
                        : eligibleItems.stream().mapToInt(i -> Optional.ofNullable(i.getQty()).orElse(1)).sum();
                List<Map<String, Object>> tiers = (List<Map<String, Object>>) params.getOrDefault("tiers", List.of());
                double matchedPct = 0.0;
                for (Map<String, Object> tier : tiers) {
                    long min = toLong(tier.get("min"));
                    if (metric >= min) {
                        matchedPct = Math.max(matchedPct, toDouble(tier.get("percent")));
                    }
                }
                discount = Math.round(eligibleSubtotal * (matchedPct / 100.0));
                target = "item";
            }
            case "bundle_price" -> {
                int pickQty = (int) toLong(params.getOrDefault("pick_qty", 2));
                long bundlePrice = toLong(params.get("bundle_price"));
                int totalEligibleQty = eligibleItems.stream().mapToInt(i -> Optional.ofNullable(i.getQty()).orElse(1)).sum();
                if (pickQty > 0 && totalEligibleQty >= pickQty && bundlePrice > 0) {
                    int bundles = totalEligibleQty / pickQty;
                    long normalPrice = (eligibleSubtotal * (long) (bundles * pickQty)) / totalEligibleQty;
                    discount = Math.max(0L, normalPrice - (bundles * bundlePrice));
                }
                target = "item";
            }
            case "free_shipping" -> {
                long maxSubsidy = toLong(params.getOrDefault("max_shipping_subsidy", shippingOriginal));
                discount = Math.min(shippingOriginal, maxSubsidy);
                target = "shipping";
            }
            case "tradein_credit" -> {
                long appraised = req.getTradein() != null ? toLong(req.getTradein().get("appraised_value")) : 0L;
                long bonus = toLong(params.get("bonus_amount"));
                long maxCredit = toLong(params.get("max_credit"));
                discount = appraised + bonus;
                if (maxCredit > 0) discount = Math.min(discount, maxCredit);
                target = "tradein";
            }
            case "cashback" -> {
                double pct = toDouble(params.getOrDefault("percent", 0));
                long cb = pct > 0 ? Math.round(subtotal * (pct / 100.0)) : toLong(params.get("amount"));
                long maxAmt = toLong(params.get("max_amount"));
                if (maxAmt > 0) cb = Math.min(cb, maxAmt);
                reward = PromoEvaluateResponse.RewardEarned.builder()
                        .promoId(promo.getId())
                        .kind("cashback")
                        .value(cb)
                        .description("Cashback " + cb)
                        .build();
            }
            case "points" -> {
                long mult = Math.max(1L, toLong(params.getOrDefault("multiplier", 1)));
                long pts = (subtotal / 1000L) * mult;
                long maxPts = toLong(params.get("max_points"));
                if (maxPts > 0) pts = Math.min(pts, maxPts);
                reward = PromoEvaluateResponse.RewardEarned.builder()
                        .promoId(promo.getId())
                        .kind("points")
                        .value(pts)
                        .description("Points earned: " + pts)
                        .build();
            }
            default -> {
                discount = toLong(params.get("amount"));
            }
        }

        long maxDiscountOrder = toLong(limits.get("max_discount_per_order"));
        if (maxDiscountOrder > 0) {
            discount = Math.min(discount, maxDiscountOrder);
        }
        return new BenefitCalculation(discount, target, reward);
    }

    @SuppressWarnings("unchecked")
    private List<PromoEvaluateRequest.CartItemInput> filterEligibleItems(
            List<PromoEvaluateRequest.CartItemInput> items,
            Map<String, Object> scope) {
        Map<String, Object> itemsScope = (Map<String, Object>) scope.get("items");
        if (itemsScope == null) return items;

        Map<String, Object> include = (Map<String, Object>) itemsScope.getOrDefault("include", Map.of());
        Map<String, Object> exclude = (Map<String, Object>) itemsScope.getOrDefault("exclude", Map.of());

        List<String> incCats = (List<String>) include.getOrDefault("categories", List.of());
        List<String> incSkus = (List<String>) include.getOrDefault("skus", List.of());
        List<String> excSkus = (List<String>) exclude.getOrDefault("skus", List.of());

        return items.stream().filter(item -> {
            if (item.getSku() != null && excSkus.contains(item.getSku())) return false;
            boolean hasIncludeFilter = !incCats.isEmpty() || !incSkus.isEmpty();
            if (!hasIncludeFilter) return true;
            boolean matchCat = item.getCategory() != null && incCats.contains(item.getCategory());
            boolean matchSku = item.getSku() != null && incSkus.contains(item.getSku());
            return matchCat || matchSku;
        }).toList();
    }

    private Map<String, Object> buildFactMap(
            PromoEvaluateRequest req,
            long subtotal,
            long eligibleSubtotal,
            int totalQty,
            int eligibleQty,
            List<PromoEvaluateRequest.CartItemInput> items) {
        Map<String, Object> facts = new HashMap<>();
        facts.put("cart.subtotal", subtotal);
        facts.put("cart.eligible_subtotal", eligibleSubtotal);
        facts.put("cart.item_qty", totalQty);
        facts.put("cart.eligible_item_qty", eligibleQty);
        facts.put("cart.distinct_sku_count", items.stream().map(PromoEvaluateRequest.CartItemInput::getSku).filter(Objects::nonNull).distinct().count());
        facts.put("cart.shipping_fee", Optional.ofNullable(req.getCart().getShippingFee()).orElse(0L));

        if (req.getCustomer() != null) {
            facts.put("customer.id", req.getCustomer().getId());
            facts.put("customer.tier", req.getCustomer().getTier());
            facts.put("customer.is_new", Boolean.TRUE.equals(req.getCustomer().getIsNew()));
            facts.put("customer.days_since_last_order", Optional.ofNullable(req.getCustomer().getDaysSinceLastOrder()).orElse(0));
            facts.put("customer.birthday_month", req.getCustomer().getBirthdayMonth());
            facts.put("customer.marketing_consent", Boolean.TRUE.equals(req.getCustomer().getMarketingConsent()));
        }
        if (req.getPayment() != null) {
            facts.put("payment.method", req.getPayment().getMethod());
            facts.put("payment.provider", req.getPayment().getProvider());
            facts.put("payment.card_bin", req.getPayment().getCardBin());
            facts.put("payment.installment_tenor", Optional.ofNullable(req.getPayment().getInstallmentTenor()).orElse(0));
        }
        if (req.getContext() != null) {
            facts.put("context.channel", req.getContext().getChannel());
            facts.put("context.coupon_code", req.getContext().getCouponCode());
            facts.put("context.store_id", req.getContext().getStoreId());
        }
        if (req.getTradein() != null) {
            req.getTradein().forEach((k, v) -> facts.put("tradein." + k, v));
        }
        return facts;
    }

    @SuppressWarnings("unchecked")
    private ConditionOutcome evaluateConditionNode(Map<String, Object> node, Map<String, Object> facts) {
        if (node == null || node.isEmpty()) {
            return ConditionOutcome.ok();
        }
        if (node.containsKey("all")) {
            List<Map<String, Object>> list = (List<Map<String, Object>>) node.get("all");
            if (list != null) {
                for (Map<String, Object> child : list) {
                    ConditionOutcome out = evaluateConditionNode(child, facts);
                    if (!out.passed) return out;
                }
            }
            return ConditionOutcome.ok();
        }
        if (node.containsKey("any")) {
            List<Map<String, Object>> list = (List<Map<String, Object>>) node.get("any");
            if (list == null || list.isEmpty()) return ConditionOutcome.ok();
            ConditionOutcome lastFail = null;
            for (Map<String, Object> child : list) {
                ConditionOutcome out = evaluateConditionNode(child, facts);
                if (out.passed) return ConditionOutcome.ok();
                lastFail = out;
            }
            return lastFail != null ? lastFail : ConditionOutcome.fail("CONDITION_NOT_MET", Map.of());
        }
        if (node.containsKey("not")) {
            Map<String, Object> child = (Map<String, Object>) node.get("not");
            ConditionOutcome out = evaluateConditionNode(child, facts);
            return out.passed ? ConditionOutcome.fail("CONDITION_EXCLUDED", Map.of()) : ConditionOutcome.ok();
        }

        // Leaf condition: { "fact": "...", "op": "...", "value": ... }
        String factKey = (String) node.get("fact");
        String op = Optional.ofNullable((String) node.get("op")).orElse("==");
        Object expected = node.get("value");
        Object actual = facts.get(factKey);

        boolean matched = compareFact(actual, op, expected);
        if (matched) return ConditionOutcome.ok();

        if (factKey != null && factKey.contains("subtotal")) {
            return ConditionOutcome.fail("MIN_SPEND_NOT_MET", Map.of(
                    "required", expected != null ? expected : 0,
                    "actual", actual != null ? actual : 0
            ));
        }
        if (factKey != null && factKey.startsWith("payment.")) {
            return ConditionOutcome.fail("PAYMENT_METHOD_NOT_ELIGIBLE", Map.of(
                    "payment_methods", String.valueOf(expected)
            ));
        }
        return ConditionOutcome.fail("CONDITION_NOT_MET", Map.of("fact", String.valueOf(factKey)));
    }

    private boolean compareFact(Object actual, String op, Object expected) {
        if (actual == null) return "not_exists".equalsIgnoreCase(op);
        return switch (op) {
            case "==" -> String.valueOf(actual).equalsIgnoreCase(String.valueOf(expected));
            case "!=" -> !String.valueOf(actual).equalsIgnoreCase(String.valueOf(expected));
            case ">=" -> toDouble(actual) >= toDouble(expected);
            case ">" -> toDouble(actual) > toDouble(expected);
            case "<=" -> toDouble(actual) <= toDouble(expected);
            case "<" -> toDouble(actual) < toDouble(expected);
            case "in", "in_list" -> {
                if (expected instanceof Collection<?> col) {
                    yield col.stream().anyMatch(x -> String.valueOf(x).equalsIgnoreCase(String.valueOf(actual)));
                }
                yield String.valueOf(expected).contains(String.valueOf(actual));
            }
            case "starts_with" -> String.valueOf(actual).startsWith(String.valueOf(expected));
            default -> true;
        };
    }

    private PromoEvaluateResponse.RejectedPromo buildRejected(
            PrmMstPromotion promo, String reasonCode, String locale, Map<String, Object> detail) {
        String template = messageCatalogRepository.findByReasonCodeAndLocale(reasonCode, locale)
                .map(PrmMstMessageCatalog::getTemplate)
                .orElse(reasonCode);
        for (Map.Entry<String, Object> e : detail.entrySet()) {
            template = template.replace("{" + e.getKey() + "}", String.valueOf(e.getValue()));
        }
        return PromoEvaluateResponse.RejectedPromo.builder()
                .promoId(promo.getId())
                .code(promo.getCode())
                .name(promo.getName())
                .reason(reasonCode)
                .message(template)
                .detail(detail)
                .build();
    }

    private String resolveDefaultGroup(String promoType) {
        if (promoType == null) return "cart_discount";
        return switch (promoType) {
            case "buy_x_get_y", "flash_sale", "fixed_price", "tiered_discount", "bundle", "early_bird" -> "item_discount";
            case "free_shipping" -> "shipping";
            case "payment_promo" -> "payment";
            case "tradein", "buyback_guarantee" -> "tradein";
            case "cashback", "points_multiplier", "referral" -> "reward";
            case "gift_with_purchase" -> "gift";
            default -> "cart_discount";
        };
    }

    private Map<String, Object> parseJsonMap(String json) {
        if (json == null || json.isBlank()) return Map.of();
        try {
            return objectMapper.readValue(json, new TypeReference<>() {});
        } catch (Exception e) {
            return Map.of();
        }
    }

    private OffsetDateTime parseTimeOrNow(String iso) {
        if (iso == null || iso.isBlank()) return OffsetDateTime.now();
        try {
            return OffsetDateTime.parse(iso);
        } catch (Exception e) {
            return OffsetDateTime.now();
        }
    }

    private long toLong(Object val) {
        if (val == null) return 0L;
        if (val instanceof Number n) return n.longValue();
        if (val instanceof Map<?, ?> m && m.get("IDR") instanceof Number n) return n.longValue();
        try {
            return Long.parseLong(String.valueOf(val));
        } catch (Exception e) {
            return 0L;
        }
    }

    private double toDouble(Object val) {
        if (val == null) return 0.0;
        if (val instanceof Number n) return n.doubleValue();
        try {
            return Double.parseDouble(String.valueOf(val));
        } catch (Exception e) {
            return 0.0;
        }
    }

    private record ConditionOutcome(boolean passed, String reasonCode, Map<String, Object> detail) {
        static ConditionOutcome ok() { return new ConditionOutcome(true, null, Map.of()); }
        static ConditionOutcome fail(String code, Map<String, Object> detail) { return new ConditionOutcome(false, code, detail); }
    }

    private record BenefitCalculation(long discountAmount, String target, PromoEvaluateResponse.RewardEarned reward) {}

    private record CandidateResult(
            PrmMstPromotion promo,
            String group,
            String stackingMode,
            BenefitCalculation calc,
            List<Map<String, Object>> funding) {}
}
