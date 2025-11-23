-- 1. Monthly Orders: Compare total orders across pre-crisis (Jan–May 2025) vs crisis (Jun–Sep 2025). How severe is the decline?
WITH CTE AS (SELECT *,MONTHNAME(order_timestamp) AS Month FROM fact_orders)
Select Month, COUNT(order_id) AS Orders FROM CTE GROUP BY Month;

-- 2. Which top 5 city groups experienced the highest percentage decline in orders during 
-- the crisis period compared to the pre-crisis period?
WITH CTE1 AS (SELECT dr.city, fo.*,MONTH(order_timestamp) AS Monthnumber FROM fact_orders fo LEFT JOIN dim_restaurant dr 
USING (restaurant_id)),
CTE2 AS (SELECT city, COUNT(order_id) AS Pre_crisis_orders FROM CTE1 WHERE Monthnumber<6 GROUP BY city),
CTE3 AS (SELECT city, COUNT(order_id) AS Crisis_orders FROM CTE1 WHERE Monthnumber>=6 GROUP BY city),
CTE4 AS (SELECT CTE2.city, Pre_crisis_orders, Crisis_orders,
ROUND((Pre_crisis_orders-Crisis_orders)*100/SUM(Pre_crisis_orders) OVER(),2) as diff_percentage
FROM CTE2 JOIN CTE3 USING (city)),
CTE5 AS (SELECT *, DENSE_RANK() OVER(ORDER BY diff_percentage DESC) AS ranking FROM CTE4)
Select * FROM CTE5 WHERE ranking<=5;

-- 3. Among restaurants with at least 50 pre-crisis orders, which top 10 high-volume restaurants experienced the largest 
-- percentage decline in order counts during the crisis period?
WITH CTE1 AS (SELECT dr.restaurant_name, fo.*,MONTH(order_timestamp) AS Monthnumber FROM fact_orders fo LEFT JOIN dim_restaurant dr 
USING (restaurant_id)),
CTE2 AS (SELECT restaurant_name, COUNT(order_id) AS Pre_crisis_orders FROM CTE1 WHERE Monthnumber<6 GROUP BY restaurant_name),
CTE3 AS (SELECT restaurant_name, COUNT(order_id) AS Crisis_orders FROM CTE1 WHERE Monthnumber>=6 GROUP BY restaurant_name),
CTE4 AS (SELECT CTE2.restaurant_name, Pre_crisis_orders, Crisis_orders FROM CTE2 JOIN CTE3 USING(restaurant_name)
WHERE Pre_crisis_orders>=50),
CTE5 AS (SELECT *, ROUND((Pre_crisis_orders-Crisis_orders)*100/Pre_crisis_orders,2) AS difference_percentage FROM CTE4),
CTE6 AS (SELECT *, DENSE_RANK() OVER(ORDER BY difference_percentage DESC) AS ranking FROM CTE5)
SELECT * FROM CTE6 WHERE ranking<=10;

-- 4. Cancellation Analysis: What is the cancellation rate trend pre-crisis vs crisis, and which cities are most affected? 
WITH CTE1 AS (SELECT dr.city, fo.*, CASE
WHEN MONTH(order_timestamp)<6 THEN 'Pre_Crisis'
WHEN MONTH(order_timestamp)>=6 THEN 'Crisis' END AS Timeline FROM fact_orders fo LEFT JOIN dim_restaurant dr USING (restaurant_id)),
CTE2 AS (SELECT city, Timeline, COUNT(order_id) AS total_orders FROM CTE1 GROUP BY city, Timeline),
CTE3 AS (SELECT city, Timeline, COUNT(order_id) AS cancelled_orders FROM CTE1 WHERE is_cancelled='Y' GROUP BY city, Timeline),
CTE4 AS (SELECT CTE2.city, CTE2.Timeline, total_orders, cancelled_orders, ROUND(cancelled_orders*100/total_orders,2) 
AS Cancellation_rate FROM CTE2 JOIN CTE3 USING (city, Timeline))
SELECT *, DENSE_RANK() OVER (PARTITION BY Timeline ORDER BY Cancellation_rate DESC) AS ranking FROM CTE4 ;

-- 5. Delivery SLA: Measure average delivery time across phases. Did SLA compliance worsen significantly in the crisis period? 
WITH CTE1 AS (SELECT dp.*,fo.order_timestamp FROM fact_delivery_performance dp LEFT JOIN fact_orders fo USING (order_id)),
CTE2 AS (SELECT *,
CASE
WHEN MONTH(order_timestamp)<6 THEN 'Pre_Crisis'
WHEN MONTH(order_timestamp)>=6 THEN 'Crisis' END AS Timeline FROM CTE1)
SELECT Timeline, ROUND(AVG(actual_delivery_time_mins),2) AS avg_actual_delivery_time_mins,
ROUND(AVG(expected_delivery_time_mins),2) AS avg_expected_delivery_time_mins,
ROUND(AVG(actual_delivery_time_mins-expected_delivery_time_mins),2) AS avg_delay_mins FROM CTE2 GROUP BY Timeline;

-- 6. Ratings Fluctuation: Track average customer rating month-by-month. Which months saw the sharpest drop? 
WITH CTE1 AS (SELECT fr.*,fo.order_timestamp FROM fact_ratings fr LEFT JOIN fact_orders fo USING (order_id)),
CTE2 AS (SELECT *, MONTHNAME(order_timestamp) as Month FROM CTE1)
SELECT Month, ROUND(AVG(rating),2) AS average_rating FROM CTE2 GROUP BY Month;

-- 8. Revenue Impact: Estimate revenue loss from pre-crisis vs crisis (based on subtotal, discount, and delivery fee).
With CTE AS (SELECT *,
CASE
WHEN MONTH(order_timestamp)<6 THEN 'Pre_Crisis'
WHEN MONTH(order_timestamp)>=6 THEN 'Crisis' END AS Timeline
FROM fact_orders)
SELECT Timeline, CONCAT(ROUND(SUM(subtotal_amount-discount_amount)/1000000,2),' M') AS Revenue FROM CTE
WHERE is_cancelled='N' GROUP BY Timeline;

-- 9. Loyalty Impact: Among customers who placed five or more orders before the crisis, determine how many stopped 
-- ordering during the crisis, and out of those, how many had an average rating above 4.5? 
WITH CTE1 AS (SELECT fo.*, fr.rating, MONTH(order_timestamp) AS Monthnumber
FROM fact_orders fo LEFT JOIN fact_ratings fr USING (order_id)),
CTE2 AS (SELECT Customer_id, COUNT(Customer_id) AS Pre_crisis_count, ROUND(AVG(rating),2) AS PreCrisis_Avg_rating FROM CTE1 
WHERE Monthnumber<6 GROUP BY Customer_id),
CTE3 AS (SELECT Customer_id, COUNT(Customer_id) AS Crisis_count FROM CTE1 WHERE Monthnumber>=6 GROUP BY Customer_id)
SELECT ROW_NUMBER() OVER() AS Sno, CTE2.*, Crisis_count FROM CTE2 LEFT JOIN CTE3 USING (customer_id) WHERE Pre_crisis_count>=5 AND
Crisis_count IS NULL AND PreCrisis_Avg_rating>4.5 ORDER BY Pre_crisis_count DESC;

-- Function
CREATE FUNCTION `get_timeline`(
order_timestamp DATETIME) RETURNS varchar(15) 
    DETERMINISTIC
BEGIN
DECLARE result VARCHAR(15);
IF MONTH(order_timestamp)<6 THEN
	SET result="Pre-Crisis";
ELSE 
	SET result="Crisis";
END IF;
RETURN result;
END
