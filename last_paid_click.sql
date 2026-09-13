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
)

SELECT
    s.visitor_id,
    s.visit_date,
    s.source AS utm_source,
    s.medium AS utm_medium,
    s.campaign AS utm_campaign,
    l.lead_id,
    l.created_at,
    l.amount,
    l.closing_reason,
    l.status_id
FROM ranked_sessions AS s
LEFT JOIN leads AS l
    ON s.visitor_id = l.visitor_id AND s.visit_date <= l.created_at
WHERE s.visit_rank = 1
ORDER BY
    l.amount DESC NULLS LAST,
    s.visit_date ASC,
    s.source ASC,
    s.medium ASC,
    s.campaign ASC;
