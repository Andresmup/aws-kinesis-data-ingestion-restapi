SELECT 
    pd.payment_type,
    SUM(pd.amount) AS total_income
FROM 
    "purchase-details-ingestion-dev-table" pd
GROUP BY 
    pd.payment_type
ORDER BY 
    total_income DESC;