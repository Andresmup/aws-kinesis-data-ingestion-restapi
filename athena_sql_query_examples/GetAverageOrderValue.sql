SELECT 
    AVG(pd.amount) AS average_order_value
FROM 
    purchase-details-ingestion-dev-table pd;