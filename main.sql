-- Identify customers who have never rented films but have made payments.

SELECT
    se_payment.customer_id
FROM public.payment AS se_payment
LEFT OUTER JOIN public.rental AS se_rental
ON se_payment.rental_id=se_rental.rental_id
WHERE se_rental.rental_id IS NULL

-- Determine the average number of films rented per customer, broken down by city.

WITH CTE_Total_Rentals AS
(
SELECT
	se_city.city,
	se_rental.customer_id,
	COUNT(se_rental.rental_id) AS Total_Rentals
FROM public.rental AS se_rental
INNER JOIN public.inventory AS se_inventory
ON se_rental.inventory_id=se_inventory.inventory_id
INNER JOIN public.store AS se_store
ON se_inventory.store_id=se_store.store_id
INNER JOIN public.address  AS se_address
ON se_store.address_id=se_address.address_id
INNER JOIN public.city AS se_city
ON se_address.city_id=se_city.city_id

GROUP BY 
    se_city.city,
	se_rental.customer_id
)

SELECT 
	city,
	ROUND(AVG(Total_Rentals),2)
FROM CTE_Total_Rentals
GROUP BY 
    city

-- Identify films that have been rented more than the average number of times and are currently not in inventory

WITH CTE_FILM_TOTAL_RENTALS AS
(
SELECT
	se_inventory.film_id,
	COUNT(DISTINCT se_rental.rental_id) AS total_rentals
FROM public.inventory se_inventory
INNER JOIN public.rental AS se_rental
ON se_rental.inventory_id = se_inventory.inventory_id
GROUP BY 
    se_inventory.film_id
)

SELECT 
	CTE_FILM_TOTAL_RENTALS.film_id,
	CTE_FILM_TOTAL_RENTALS.total_rentals
FROM CTE_FILM_TOTAL_RENTALS
LEFT OUTER JOIN public.inventory AS se_inventory
ON CTE_FILM_TOTAL_RENTALS.film_id=se_inventory.film_id
WHERE CTE_FILM_TOTAL_RENTALS.total_rentals > (SELECT AVG(total_rentals) FROM CTE_FILM_TOTAL_RENTALS) 
AND se_inventory.inventory_id IS NULL

-- Calculate the replacement cost of lost films for each store, considering the rental history.

SELECT
	se_inventory.store_id,
	SUM(se_film.replacement_cost) AS total_replacement_cost
FROM public.rental AS se_rental
INNER JOIN public.inventory AS se_inventory
ON se_rental.inventory_id=se_inventory.inventory_id
INNER JOIN public.film AS se_film
ON se_inventory.film_id=se_film.film_id
WHERE se_rental.return_date IS NULL
GROUP BY
	se_inventory.store_id

--Create a report that shows the top 5 most rented films in each category, 
-- along with their corresponding rental counts and revenue.

WITH CTE_Total_rentals_category AS
(
SELECT
	se_category.name,
	se_film.film_id,
	COUNT(se_rental.rental_ID) AS Total_rentals,
	SUM(se_payment.amount) AS Revenue
FROM public.rental AS se_rental
LEFT OUTER JOIN public.payment AS se_payment
ON se_rental.rental_id=se_payment.rental_id
INNER JOIN public.inventory AS se_inventory
ON se_rental.inventory_id=se_inventory.inventory_id
INNER JOIN public.film AS se_film
ON se_inventory.film_id=se_film.film_id
INNER JOIN public.film_category AS se_film_category
ON se_film.film_id=se_film_category.film_id
INNER JOIN public.category AS se_category
ON se_film_category.category_id=se_category.category_id
GROUP BY 
    se_category.name,
	se_film.film_id
ORDER BY 
    se_category.name, COUNT(se_rental.rental_ID) DESC
)


SELECT *
FROM (
    SELECT CTE_Total_rentals_category.name,
	       CTE_Total_rentals_category.film_id, 
		   CTE_Total_rentals_category.Total_rentals,
	       CTE_Total_rentals_category.Revenue,
	ROW_NUMBER() 
	OVER 
	(PARTITION BY CTE_Total_rentals_category.name
	 ORDER BY CTE_Total_rentals_category.Total_rentals  DESC) AS RANK
     FROM CTE_Total_rentals_category
) AS top_5
WHERE RANK <= 5

-- Develop a query that automatically updates the top 10 most frequently rented films.

SELECT
	se_film.title,
    COUNT(se_rental.rental_ID) AS Total_rentals
FROM public.rental AS se_rental
INNER JOIN public.inventory AS se_inventory
ON se_rental.inventory_id=se_inventory.inventory_id
INNER JOIN public.film AS se_film
ON se_inventory.film_id=se_film.film_id
WHERE CAST(se_rental.rental_date AS DATE)=CURRENT_DATE
GROUP BY 
	se_film.title
ORDER BY 
	COUNT(se_rental.rental_ID) DESC
LIMIT 10


-- Identify stores where the revenue from film rentals exceeds the revenue from payments for all customers.

WITH CTE_REVENUES_PAYMENT AS
(
SELECT
	se_payment.payment_id,
	COALESCE(se_payment.amount,0) AS payment_revenues
FROM public.payment AS se_payment
WHERE se_payment.rental_id IS NULL

),

CTE_REVENUES_RENTAL AS
(
SELECT
	se_payment.payment_id,
	COALESCE(se_payment.amount,0) AS rental_revenues
FROM public.payment AS se_payment
WHERE se_payment.rental_id IS NOT NULL
)

SELECT
	se_store.store_id,
	COALESCE(SUM(CTE_REVENUES_PAYMENT.payment_revenues),0) AS payment_revenues,
	COALESCE(SUM(CTE_REVENUES_RENTAL.rental_revenues),0) AS rental_revenues
FROM public.payment AS se_payment
INNER JOIN public.staff AS se_staff
ON se_payment.staff_id=se_staff.staff_id
INNER JOIN public.store AS se_store
ON se_staff.store_id=se_store.store_id
LEFT OUTER JOIN CTE_REVENUES_PAYMENT
ON se_payment.payment_id=CTE_REVENUES_PAYMENT.payment_id
LEFT OUTER JOIN CTE_REVENUES_RENTAL
ON se_payment.payment_id=CTE_REVENUES_RENTAL.payment_id
GROUP BY
	se_store.store_id
HAVING COALESCE(SUM(CTE_REVENUES_PAYMENT.payment_revenues),0)>COALESCE(SUM(CTE_REVENUES_RENTAL.rental_revenues),0)

-- Determine the average rental duration and total revenue for each store.

SELECT
	se_staff.store_id,
	ROUND(AVG(se_film.rental_duration),2) AS avg_rental_duration,
	SUM(se_payment.amount) AS total_revenue
FROM public.staff AS se_staff
INNER JOIN public.payment AS se_payment
ON se_staff.staff_id=se_payment.staff_id
INNER JOIN public.rental AS se_rental
ON se_payment.rental_id=se_rental.rental_id
INNER JOIN public.inventory AS se_inventory
ON se_rental.inventory_id=se_inventory.inventory_id
INNER JOIN public.film AS se_film
ON se_inventory.film_id=se_film.film_id
GROUP BY
	se_staff.store_id

-- Analyze the seasonal variation in rental activity and payments for each store.

SELECT
	EXTRACT(MONTH FROM se_rental.rental_date) as month,
	EXTRACT(YEAR FROM se_rental.rental_date) as year,
	se_inventory.store_id,
	COUNT(se_rental.rental_id) AS total_rentals,
	COALESCE(SUM(se_payment.amount),0) AS Total_amount
FROM public.rental AS se_rental
LEFT JOIN public.payment AS se_payment
ON se_rental.rental_id=se_payment.rental_id
INNER JOIN public.inventory AS se_inventory
ON se_rental.inventory_id=se_inventory.inventory_id
GROUP BY 
	EXTRACT(MONTH FROM se_rental.rental_date),
	EXTRACT(YEAR FROM se_rental.rental_date),
	se_inventory.store_id
ORDER BY
	EXTRACT(YEAR FROM se_rental.rental_date)

--- For both stores the season with the most rental activity was during July and August along with the revenues.
--  The lowest activity is during february 2006
-- However there were rentals in May where was no amount paid for the rented movies