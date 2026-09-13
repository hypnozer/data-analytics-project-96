-- Dashboard input queries. Date and UTM filters are applied in dashboard.html.
-- Traffic: count distinct visitors again for each selected period and grouping.
SELECT
    visitor_id,
    visit_date::DATE,
    source,
    medium,
    campaign
FROM sessions;

-- Costs: retain spending even when no attributed visit has matching UTM tags.
SELECT
    campaign_date::DATE AS visit_date,
    utm_source,
    utm_medium,
    utm_campaign,
    SUM(daily_spent) AS total_cost
FROM (
    SELECT
        campaign_date,
        utm_source,
        utm_medium,
        utm_campaign,
        daily_spent
    FROM vk_ads
    UNION ALL
    SELECT
        campaign_date,
        utm_source,
        utm_medium,
        utm_campaign,
        daily_spent
    FROM ya_ads
) AS ads
GROUP BY campaign_date::DATE, utm_source, utm_medium, utm_campaign;

-- Calendar lead creation is distinct from attribution by visit date.
SELECT
    visitor_id,
    created_at::DATE,
    amount,
    status_id
FROM leads;


-- Campaign metrics for the full June cohort.
WITH ranked_sessions AS (
    SELECT
        visitor_id,
        visit_date,
        source,
        medium,
        campaign,
        ROW_NUMBER() OVER (
            PARTITION BY visitor_id
            ORDER BY
                visit_date DESC, source ASC, medium ASC,
                campaign ASC, content ASC
        ) AS visit_rank
    FROM sessions
    WHERE medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),

attribution AS (
    SELECT
        s.source AS utm_source,
        s.medium AS utm_medium,
        s.campaign AS utm_campaign,
        COUNT(*) AS visitors_count,
        COUNT(l.lead_id) AS leads_count,
        COUNT(l.lead_id) FILTER (WHERE l.status_id = 142) AS purchases_count,
        COALESCE(SUM(l.amount) FILTER (WHERE l.status_id = 142), 0) AS revenue
    FROM ranked_sessions AS s
    LEFT JOIN leads AS l
        ON s.visitor_id = l.visitor_id AND s.visit_date <= l.created_at
    WHERE s.visit_rank = 1
    GROUP BY s.source, s.medium, s.campaign
),

costs AS (
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM (
        SELECT
            utm_source,
            utm_medium,
            utm_campaign,
            daily_spent
        FROM vk_ads
        UNION ALL
        SELECT
            utm_source,
            utm_medium,
            utm_campaign,
            daily_spent
        FROM ya_ads
    ) AS ads
    GROUP BY utm_source, utm_medium, utm_campaign
),

campaign_totals AS (
    SELECT
        c.total_cost,
        COALESCE(v.utm_source, c.utm_source) AS utm_source,
        COALESCE(v.utm_medium, c.utm_medium) AS utm_medium,
        COALESCE(v.utm_campaign, c.utm_campaign) AS utm_campaign,
        COALESCE(v.visitors_count, 0) AS visitors_count,
        COALESCE(v.leads_count, 0) AS leads_count,
        COALESCE(v.purchases_count, 0) AS purchases_count,
        COALESCE(v.revenue, 0) AS revenue
    FROM attribution AS v
    FULL JOIN costs AS c
        ON
            v.utm_source = c.utm_source
            AND v.utm_medium = c.utm_medium
            AND v.utm_campaign = c.utm_campaign
)

SELECT
    *,
    total_cost::NUMERIC / NULLIF(visitors_count, 0) AS cpu,
    total_cost::NUMERIC / NULLIF(leads_count, 0) AS cpl,
    total_cost::NUMERIC / NULLIF(purchases_count, 0) AS cppu,
    (revenue - total_cost)::NUMERIC / NULLIF(total_cost, 0) * 100 AS roi,
    leads_count::NUMERIC / NULLIF(visitors_count, 0) * 100 AS visit_to_lead,
    purchases_count::NUMERIC / NULLIF(leads_count, 0) * 100 AS lead_to_purchase
FROM campaign_totals
ORDER BY total_cost DESC NULLS LAST;

-- Source metrics: ratios calculated from aggregated totals.
WITH ranked_sessions AS (
    SELECT
        visitor_id,
        visit_date,
        source,
        medium,
        campaign,
        ROW_NUMBER() OVER (
            PARTITION BY visitor_id
            ORDER BY
                visit_date DESC, source ASC, medium ASC,
                campaign ASC, content ASC
        ) AS visit_rank
    FROM sessions
    WHERE medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),

attribution AS (
    SELECT
        s.source AS utm_source,
        s.medium AS utm_medium,
        s.campaign AS utm_campaign,
        COUNT(*) AS visitors_count,
        COUNT(l.lead_id) AS leads_count,
        COUNT(l.lead_id) FILTER (WHERE l.status_id = 142) AS purchases_count,
        COALESCE(SUM(l.amount) FILTER (WHERE l.status_id = 142), 0) AS revenue
    FROM ranked_sessions AS s
    LEFT JOIN leads AS l
        ON s.visitor_id = l.visitor_id AND s.visit_date <= l.created_at
    WHERE s.visit_rank = 1
    GROUP BY s.source, s.medium, s.campaign
),

costs AS (
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM (
        SELECT
            utm_source,
            utm_medium,
            utm_campaign,
            daily_spent
        FROM vk_ads
        UNION ALL
        SELECT
            utm_source,
            utm_medium,
            utm_campaign,
            daily_spent
        FROM ya_ads
    ) AS ads
    GROUP BY utm_source, utm_medium, utm_campaign
),

campaign_totals AS (
    SELECT
        c.total_cost,
        COALESCE(v.utm_source, c.utm_source) AS utm_source,
        COALESCE(v.utm_medium, c.utm_medium) AS utm_medium,
        COALESCE(v.utm_campaign, c.utm_campaign) AS utm_campaign,
        COALESCE(v.visitors_count, 0) AS visitors_count,
        COALESCE(v.leads_count, 0) AS leads_count,
        COALESCE(v.purchases_count, 0) AS purchases_count,
        COALESCE(v.revenue, 0) AS revenue
    FROM attribution AS v
    FULL JOIN costs AS c
        ON
            v.utm_source = c.utm_source
            AND v.utm_medium = c.utm_medium
            AND v.utm_campaign = c.utm_campaign
),

source_totals AS (
    SELECT
        utm_source,
        SUM(visitors_count) AS visitors_count,
        SUM(leads_count) AS leads_count,
        SUM(purchases_count) AS purchases_count,
        SUM(revenue) AS revenue,
        SUM(total_cost) AS total_cost
    FROM campaign_totals
    GROUP BY utm_source
)

SELECT
    *,
    total_cost::NUMERIC / NULLIF(visitors_count, 0) AS cpu,
    total_cost::NUMERIC / NULLIF(leads_count, 0) AS cpl,
    total_cost::NUMERIC / NULLIF(purchases_count, 0) AS cppu,
    (revenue - total_cost)::NUMERIC / NULLIF(total_cost, 0) * 100 AS roi,
    leads_count::NUMERIC / NULLIF(visitors_count, 0) * 100 AS visit_to_lead,
    purchases_count::NUMERIC / NULLIF(leads_count, 0) * 100 AS lead_to_purchase
FROM source_totals
ORDER BY total_cost DESC NULLS LAST;

-- Presentation analysis queries.
-- Overall site and CRM volume, separate from paid attribution.
SELECT
    COUNT(*) AS sessions_count,
    COUNT(DISTINCT visitor_id) AS users_count
FROM sessions;

SELECT
    COUNT(*) AS leads_count,
    COUNT(*) FILTER (WHERE status_id = 142) AS purchases_count,
    SUM(amount) FILTER (WHERE status_id = 142) AS revenue
FROM leads;

-- Time to lead creation, not time to closure: no closure timestamp exists.
WITH last_paid AS (
    SELECT
        visitor_id,
        MAX(visit_date) AS visit_date
    FROM sessions
    WHERE medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
    GROUP BY visitor_id
)

SELECT
    COUNT(*) AS attributed_leads,
    PERCENTILE_CONT(0.9) WITHIN GROUP (
        ORDER BY EXTRACT(EPOCH FROM (l.created_at - s.visit_date)) / 86400
    ) AS activity_dates_to_create_90_percent,
    COUNT(*) FILTER (WHERE l.status_id IN (142, 143)) AS closed_leads
FROM last_paid AS s
INNER JOIN leads AS l
    ON s.visitor_id = l.visitor_id AND s.visit_date <= l.created_at;

-- Daily advertising spend and organic visitors. Correlation is descriptive.
WITH organic AS (
    SELECT
        visit_date::DATE AS activity_date,
        COUNT(DISTINCT visitor_id) AS organic_users
    FROM sessions
    WHERE medium = 'organic'
    GROUP BY visit_date::DATE
),

ads AS (
    SELECT
        campaign_date::DATE AS activity_date,
        SUM(daily_spent) AS spent
    FROM (
        SELECT
            campaign_date,
            daily_spent
        FROM vk_ads
        UNION ALL
        SELECT
            campaign_date,
            daily_spent
        FROM ya_ads
    ) AS all_ads
    GROUP BY campaign_date::DATE
)

SELECT
    o.activity_date,
    o.organic_users,
    COALESCE(a.spent, 0) AS spent
FROM organic AS o
LEFT JOIN ads AS a ON o.activity_date = a.activity_date
ORDER BY o.activity_date;
