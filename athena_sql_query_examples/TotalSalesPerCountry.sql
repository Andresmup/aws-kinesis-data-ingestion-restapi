SELECT 
    sa.country,
    SUM(pd.amount) AS total_sales
FROM 
    purchase-details-ingestion-dev-table pd
JOIN 
    shipping-addresses-ingestion-dev-table sa ON pd.order_id = sa.order_id
GROUP BY 
    sa.country
ORDER BY 
    total_sales DESC;