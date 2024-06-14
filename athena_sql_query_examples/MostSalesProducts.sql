SELECT 
    p.name,
    SUM(p.quantity) AS total_quantity_sold
FROM 
    "product-details-ingestion-dev-table" p
GROUP BY 
    p.name
ORDER BY 
    total_quantity_sold DESC;