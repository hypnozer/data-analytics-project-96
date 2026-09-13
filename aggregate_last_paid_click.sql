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

attributed_visits AS (
    SELECT
        s.visit_date::DATE AS visit_date,
        s.source AS utm_source,
        s.medium AS utm_medium,
        s.campaign AS utm_campaign,
        COUNT(*) AS visitors_count,
        COUNT(l.lead_id) AS leads_count,
        COUNT(l.lead_id) FILTER (WHERE l.status_id = 142) AS purchases_count,
        SUM(l.amount) FILTER (WHERE l.status_id = 142) AS revenue
    FROM ranked_sessions AS s
    LEFT JOIN leads AS l
        ON s.visitor_id = l.visitor_id AND s.visit_date <= l.created_at
    WHERE s.visit_rank = 1
    GROUP BY 1, 2, 3, 4
),

all_ads AS (
    SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent
    FROM vk_ads
    UNION ALL
    SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent
    FROM ya_ads
),

advertising_costs AS (
    SELECT
        campaign_date::DATE AS visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        SUM(daily_spent) AS total_cost
    FROM all_ads
    GROUP BY 1, 2, 3, 4
)

SELECT
    v.visit_date,
    v.visitors_count,
    v.utm_source,
    v.utm_medium,
    v.utm_campaign,
    a.total_cost,
    v.leads_count,
    v.purchases_count,
    v.revenue
FROM attributed_visits AS v
LEFT JOIN advertising_costs AS a
    ON
        v.visit_date = a.visit_date
        AND v.utm_source = a.utm_source
        AND v.utm_medium = a.utm_medium
        AND v.utm_campaign = a.utm_campaign
ORDER BY
    v.revenue DESC NULLS LAST,
    v.visit_date ASC,
    v.visitors_count DESC,
    v.utm_source ASC,
    v.utm_medium ASC,
    v.utm_campaign ASC;
