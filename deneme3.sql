--**Level 3 - Expert**
select * from categories
select * from customers
select * from employees
select * from orders
select * from order_details
select * from products
select * from shippers
select * from suppliers

-- ALISTIRMA 1
--Total_Revenue adlı bir geçici tablo (CTE) oluşturuyor.
-- Bu kısımda her müşteri ve sipariş için toplam satış geliri hesaplanmış oldu.
WITH Total_Revenue AS ( --Her ürünün toplam satış gelirini hesaplıyor.
SELECT
	c.customer_id, o.order_id, o.order_date,
	SUM(od.unit_price * od.quantity * (1 - od.discount)) AS total_revenue
	FROM customers c
	--customers, orders ve order_details tablolarını birbirine bağlıyor.
	JOIN orders o ON c.customer_id = o.customer_id
	JOIN order_details od ON o.order_id = od.order_id
	GROUP BY c.customer_id, o.order_id ,o.order_date
),

--Total_Revenue tablosundaki verileri kullanıyor.
--Her müşteri için siparişleri en yeni tarihli olana göre sıralıyor (ORDER BY tr.order_date DESC).
--ROW_NUMBER() OVER (...) fonksiyonu ile her müşterinin siparişlerine bir sıra numarası veriyor.
--PARTITION BY tr.customer_id: Her müşteriyi kendi içinde değerlendiriyor (müşteri bazında sıralama yapıyor).
-- ORDER BY tr.order_date DESC: Siparişleri en güncel tarihli olan en üstte olacak şekilde sıralıyor.
RankedOrders AS ( 
SELECT
	customer_id,order_id, order_date, total_revenue,
	ROW_NUMBER() OVER (PARTITION BY tr.customer_id ORDER BY tr.order_date DESC) AS order_row
FROM Total_Revenue tr
)
-- Bu adımda, her müşterinin siparişleri için sıralama numarası oluşturulmuş oldu.
--Ana sorgumuz
--RankedOrders geçici tablosunu kullanarak sadece en son 3 siparişi alıyor (WHERE order_row <= 3).
SELECT
	customer_id,
	order_id,
	order_date,
	total_revenue
FROM RankedOrders
WHERE order_row <= 3
ORDER BY customer_id, order_date DESC;


-- ALISTIRMA 2

SELECT 
	c.customer_id,
	c.contact_name,
	p.product_id,
	p.product_name,
	COUNT(DISTINCT o.order_id) AS times_order
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_details od ON o.order_id = od.order_id
JOIN products p ON od.product_id = p.product_id
GROUP BY c.customer_id, c.contact_name, p.product_id, p.product_name
HAVING COUNT(DISTINCT o.order_id) >= 3
ORDER BY c.customer_id, p.product_id

--ALISTIRMA 3 
WITH OrderCounts AS (
    -- Her çalışanın günlük sipariş sayısını hesaplıyoruz
    SELECT
        e.employee_id,
        o.order_date,
        COUNT(o.order_id) AS order_count
    FROM orders o
    JOIN employees e ON o.employee_id = e.employee_id
    JOIN order_details od ON od.order_id = o.order_id
    GROUP BY e.employee_id, o.order_date
),

Rolling30Days AS (
    -- Her çalışanın 30 günlük sipariş toplamını hesaplıyoruz
    SELECT
        employee_id,
        order_date,
        SUM(order_count) OVER (
            PARTITION BY employee_id
            ORDER BY order_date
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        ) AS last_30_days_orders
    FROM OrderCounts
)

-- Ana sorgumuz
SELECT 
    employee_id,
    order_date,
    last_30_days_orders AS current_30_days_orders,
    LAG(last_30_days_orders, 30) OVER (
        PARTITION BY employee_id ORDER BY order_date
    ) AS previous_30_days_orders,
    
    -- Sipariş değişimini hesaplıyoruz
    last_30_days_orders - LAG(last_30_days_orders, 30) OVER (
        PARTITION BY employee_id ORDER BY order_date
    ) AS order_change, -- BURADA VİRGÜL EKSİKTİ, EKLENDİ!
    
    -- Performans değerlendirmesi
    CASE 
        WHEN last_30_days_orders - LAG(last_30_days_orders, 30) OVER (
            PARTITION BY employee_id ORDER BY order_date
        ) > 0 THEN 'Positive increase'
        WHEN last_30_days_orders - LAG(last_30_days_orders, 30) OVER (
            PARTITION BY employee_id ORDER BY order_date
        ) < 0 THEN 'Negative decrease'
        ELSE 'No Change'
    END AS performance

FROM Rolling30Days
ORDER BY employee_id, order_date DESC;

--ALISTIRMA 4
WITH DiscountTrend AS (
	SELECT 
	    c.customer_id,
	    c.contact_name,
	    DATE_TRUNC('month', o.order_date) AS order_month,  -- Sipariş tarihini aylık bazda grupluyoruz
	    AVG(od.discount) AS avg_discount_rate,  -- İndirim oranlarının ortalamasını alıyoruz.
		AVG(AVG(od.discount)) OVER (
            PARTITION BY c.customer_id 
            ORDER BY DATE_TRUNC('month', o.order_date) 
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS moving_avg_discount,  --Son 3 ayın hareketli ortalamasını (moving average) hesaplar.
		LAG(AVG(od.discount)) OVER (
            PARTITION BY c.customer_id 
            ORDER BY DATE_TRUNC('month', o.order_date)
        ) AS previous_avg_discount  -- Bir önceki ayın ortalama indirim oranını alır.
	FROM customers c
	JOIN orders o ON c.customer_id = o.customer_id 
	JOIN order_details od ON o.order_id = od.order_id
	GROUP BY c.customer_id, c.contact_name, order_month
)
--Ana sorgu
SELECT *,
       CASE 
           WHEN moving_avg_discount > previous_avg_discount THEN 'Artış'
           WHEN moving_avg_discount < previous_avg_discount THEN 'Azalış'
           ELSE 'Değişim Yok'
       END AS trend
FROM DiscountTrend
ORDER BY customer_id, order_month;
