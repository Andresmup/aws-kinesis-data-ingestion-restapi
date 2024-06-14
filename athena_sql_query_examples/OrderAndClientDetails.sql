SELECT 
    o.customer_id,
    o.order_id,
    o.order_date,
    o.status,
    sa.country,
    sa.state,
    sa.city,
    sa.street,
    sa.zip
FROM 
    "orders-ingestion-dev-table" o
JOIN 
    "shipping-addresses-ingestion-dev-table" sa ON o.order_id = sa.order_id;