-- Step 1
DROP VIEW IF EXISTS payments_with_month_idx;
CREATE VIEW payments_with_month_idx AS
SELECT
    p.user_id, p.payment_date, p.amount, p.status,
    u.acquisition_channel, u.country, u.plan_type, u.signup_date,
    (  (CAST(strftime('%Y', p.payment_date) AS INT) - CAST(strftime('%Y', u.signup_date) AS INT)) * 12
     + (CAST(strftime('%m', p.payment_date) AS INT) - CAST(strftime('%m', u.signup_date) AS INT)) ) AS month_idx
FROM subscription_payments p
JOIN users u ON u.user_id = p.user_id;


-- Step 2
WITH channel_users AS (
    SELECT acquisition_channel, COUNT(*) AS n_users FROM users GROUP BY acquisition_channel
),
monthly_rev AS (
    SELECT acquisition_channel, month_idx, SUM(amount) AS total_amount
    FROM payments_with_month_idx
    WHERE month_idx BETWEEN 0 AND 3
    GROUP BY acquisition_channel, month_idx
)
SELECT
    m.acquisition_channel, m.month_idx + 1 AS billing_month,
    ROUND(m.total_amount, 2) AS total_revenue, c.n_users,
    ROUND(m.total_amount / c.n_users, 3) AS avg_revenue_per_user
FROM monthly_rev m
JOIN channel_users c ON c.acquisition_channel = m.acquisition_channel
ORDER BY m.acquisition_channel, billing_month;


-- Step 3
WITH channel_users AS (
    SELECT acquisition_channel, COUNT(*) AS n_users FROM users GROUP BY acquisition_channel
),
first4 AS (
    SELECT acquisition_channel, SUM(amount) AS total_amount
    FROM payments_with_month_idx
    WHERE month_idx BETWEEN 0 AND 3
    GROUP BY acquisition_channel
)
SELECT
    f.acquisition_channel, c.n_users,
    ROUND(f.total_amount, 2) AS total_revenue_first_4mo,
    ROUND(f.total_amount / c.n_users, 2) AS ltv_4mo
FROM first4 f
JOIN channel_users c ON c.acquisition_channel = f.acquisition_channel
ORDER BY ltv_4mo DESC;


-- Step 4
WITH first_churn AS (
    SELECT user_id, MIN(month_idx) AS churn_month_idx
    FROM payments_with_month_idx
    WHERE status = 'churned'
    GROUP BY user_id
)
SELECT
    u.acquisition_channel, COUNT(*) AS n_users,
    SUM(CASE WHEN fc.churn_month_idx <= 3 THEN 1 ELSE 0 END) AS churned_within_4mo,
    ROUND(1.0 * SUM(CASE WHEN fc.churn_month_idx <= 3 THEN 1 ELSE 0 END) / COUNT(*), 3) AS churn_rate_4mo
FROM users u
LEFT JOIN first_churn fc ON fc.user_id = u.user_id
GROUP BY u.acquisition_channel
ORDER BY churn_rate_4mo DESC;


-- Step 5
WITH spend_per_channel AS (
    SELECT channel, SUM(spend) AS total_spend FROM marketing_spend GROUP BY channel
),
signups_per_channel AS (
    SELECT acquisition_channel, COUNT(*) AS n_signups FROM users GROUP BY acquisition_channel
),
ltv_per_channel AS (
    SELECT acquisition_channel, SUM(amount) * 1.0 / COUNT(DISTINCT user_id) AS ltv_4mo
    FROM payments_with_month_idx
    WHERE month_idx BETWEEN 0 AND 3
    GROUP BY acquisition_channel
)
SELECT
    s.acquisition_channel, s.n_signups,
    ROUND(sp.total_spend, 2) AS total_spend,
    ROUND(sp.total_spend / s.n_signups, 2) AS cpa,
    ROUND(l.ltv_4mo, 2) AS ltv_4mo,
    ROUND(l.ltv_4mo / (sp.total_spend / s.n_signups), 2) AS ltv_to_cac_ratio
FROM signups_per_channel s
JOIN spend_per_channel sp ON sp.channel = s.acquisition_channel
JOIN ltv_per_channel l ON l.acquisition_channel = s.acquisition_channel
ORDER BY ltv_to_cac_ratio DESC;
