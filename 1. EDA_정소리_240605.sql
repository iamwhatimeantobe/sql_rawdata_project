-- 중복값이 있어서 삭제하는 것 먼저 진행
CREATE TEMPORARY TABLE raw AS 
	SELECT DISTINCT event_time, event_type, product_id, brand, price, user_id, user_session
	FROM 2019dec;
    
CREATE TEMPORARY TABLE vt AS 
	SELECT user_id, user_session, event_time, product_id
	FROM raw
	WHERE event_type = 'view';
CREATE TEMPORARY TABLE ct AS 
	SELECT user_id, user_session, event_time, product_id
	FROM raw
	WHERE event_type = 'cart';
CREATE TEMPORARY TABLE pt AS 
	SELECT user_id, user_session, event_time, product_id
	FROM raw
	WHERE event_type = 'purchase';
CREATE TEMPORARY TABLE rt AS 
	SELECT user_id, user_session, event_time, product_id
	FROM raw
	WHERE event_type = 'remove_from_cart';
CREATE TEMPORARY TABLE v_to_c AS  -- 같은 아이디, 같은 세션, 같은 제품에 대해서 view 후 cart에 넣은 데이터들을 추출하는 테이블
	SELECT vt.*
		, ct.event_time AS cart_event_time
		, TIMESTAMPDIFF(SECOND, vt.event_time, ct.event_time) AS time_gap
	FROM vt
	LEFT JOIN ct ON vt.user_id = ct.user_id
			AND vt.user_session = ct.user_session
			AND vt.product_id = ct.product_id
			AND vt.event_time <= ct.event_time;
CREATE TEMPORARY TABLE c_to_r AS  -- 같은 아이디, 같은 세션, 같은 제품에 대해서 카트를 넣은 시간보다 카트 제거한 시간이 더 늦을 경우에 속하는 값들을 추출하는 테이블
	SELECT ct.*
		, rt.event_time AS remove_event_time
		, TIMESTAMPDIFF(SECOND, ct.event_time, rt.event_time) AS time_gap
	FROM ct
	LEFT JOIN rt ON ct.user_id = rt.user_id
			AND ct.user_session = rt.user_session
			AND ct.product_id = rt.product_id
			AND ct.event_time <= rt.event_time;
CREATE TEMPORARY TABLE c_to_p AS  -- 같은 아이디, 같은 세션, 같은 제품에 대해서 카트에 넣고 구매로 이어진 값을 추출하는 테이블
	SELECT ct.*
		, pt.event_time AS purchase_event_time
		, TIMESTAMPDIFF(SECOND, ct.event_time, pt.event_time) AS time_gap
	FROM ct
	LEFT JOIN pt ON ct.user_id = pt.user_id
			AND ct.user_session = pt.user_session
			AND ct.product_id = pt.product_id
			AND ct.event_time <= pt.event_time;


SELECT * -- 테이블 내용 확인하고 싶을 때
FROM 2019dec
LIMIT 10;

#중복이 있는 것 같은데 '3533286'개
SELECT COUNT(user_id)
FROM 2019dec;

#중복을 없애보자 '3349426' - 중복된 값이 있는 것 같다. 이걸로 작업한다.
SELECT COUNT(DISTINCT event_time, event_type, product_id, brand, price, user_id, user_session)
FROM 2019dec;

SELECT *
FROM c_to_r
LIMIT 10;

#19년도 12월의 상황을 진단하고, 카트에서 물건을 빼는 현상을 포착하고 이 문제에 대해서 좀더 자세히 진단하고 싶다
#그래서 현상을 파악하고 카트에서 제외하는 비율을 좀 줄이고 싶다.

#12월 전체 들어온 view 유효 로그는 얼마만큼인가? - 794471건
SELECT COUNT(DISTINCT user_id, user_session)
FROM vt;

#cart에 넣은 건수 -  165571건
SELECT COUNT(DISTINCT user_id, user_session)
FROM ct;

#장바구니에 넣었다가 취소한 건수은? - 84668건
SELECT COUNT(DISTINCT user_id, user_session)
FROM rt;

#이게 전체 중 얼만큼의 비율일까?
# view > cart > remove 비율 확인
SELECT COUNT(DISTINCT vt.user_id, vt.user_session) AS view_count
 	, COUNT(DISTINCT ct.user_id, ct.user_session) AS cart_count
    , COUNT(DISTINCT rt.user_id, rt.user_session) AS remove_count
    , COUNT(DISTINCT ct.user_id, ct.user_session) / COUNT(DISTINCT vt.user_id, vt.user_session) AS view_cart_ratio
    , COUNT(DISTINCT rt.user_id, rt.user_session) / COUNT(DISTINCT ct.user_id, ct.user_session) AS cart_remove_ratio
	-- , COUNT(DISTINCT rt.user_id, rt.user_session) / COUNT(DISTINCT vt.user_id, vt.user_session) AS view_remove_ratio #이건 의미가 없는 값인 것 같은데. 전체 뷰에서 삭제를 봐서 뭐하지
FROM vt
LEFT JOIN ct ON vt.user_id = ct.user_id
		AND vt.user_session = ct.user_session
        AND vt.event_time <= ct.event_time
LEFT JOIN rt ON ct.user_id = rt.user_id
		AND ct.user_session = rt.user_session
        AND ct.event_time <= rt.event_time;

#위 쿼리의 결과로 총 14.93%로 본 제품을 카트에 넣고, 그 중 38.2%가 카트에서 물건을 뺐다. 
#참고로 카트에서 구매로 이어진 비율은 15.82%이다. 카트에 들어갔을 때 구매로 이어지게 하는 것이 매출을 높이는데 큰 이득이 될 것이다.

#어떤 제품에서 카트 제거가 많이 이루어졌을까? 몇 차례나?
SELECT product_id, COUNT(product_id)
FROM c_to_r
GROUP BY product_id
ORDER BY COUNT(product_id) DESC;

#여기에 나온 id가 어떤 제품인지 알아보는 게 필요하다.
WITH rpt AS (
	SELECT product_id, COUNT(product_id) count
	FROM c_to_r
	GROUP BY product_id
	ORDER BY COUNT(product_id) DESC
)
SELECT DISTINCT raw.product_id, raw.brand, raw.price, rpt.count
FROM raw
INNER JOIN rpt ON rpt.product_id = raw.product_id
ORDER BY rpt.count DESC;

#다른 걸로 돌아와서
#어떤 아이디가 카트 제거를 많이했을까? 몇 차례나? - 동일한 걸 여러 번 했을 수도 있으니까 DISTINCT를 사용하지 않음
SELECT user_id, COUNT(product_id)
FROM c_to_r
GROUP BY user_id
ORDER BY COUNT(product_id) DESC;

#카트제거가 많았던 제품과 유저의 연관관계가 있을까?



#ID별 구매로 가는데 걸리는 시간 체크
SELECT MIN(forward_avg), MAX(forward_avg)
FROM (
	SELECT user_id, ROUND(AVG(time_gap), 2) AS forward_avg
	FROM (
		SELECT vt.*
			, pt.event_time AS purchase_event_time
			, TIMESTAMPDIFF(SECOND, vt.event_time, pt.event_time) AS time_gap
		FROM vt
		LEFT JOIN pt ON vt.user_id = pt.user_id
				AND vt.user_session = pt.user_session
				AND vt.product_id = pt.product_id
				AND vt.event_time <= pt.event_time
	) v_to_p
	GROUP BY user_id
	ORDER BY forward_avg DESC
) avg_times;


#view에서 cart가는데 걸리는 시간
SELECT user_id, ROUND(AVG(time_gap), 2) AS foward_avg
FROM v_to_c
GROUP BY user_id
ORDER BY foward_avg DESC;


WITH brand_sales AS (
    SELECT
        brand,
        SUM(price) AS total_sales,
        COUNT(DISTINCT user_id) AS purchase_count
    FROM
        2019dec
    WHERE event_type = 'purchase'
    GROUP BY brand
),
sales_ranking AS (
    SELECT
        brand,
        total_sales,
        ROW_NUMBER() OVER (ORDER BY total_sales DESC) AS sales_rank
    FROM
        brand_sales
),
purchase_ranking AS (
    SELECT
        brand,
        purchase_count,
        ROW_NUMBER() OVER (ORDER BY purchase_count DESC) AS purchase_rank
    FROM
        brand_sales
)
SELECT
    s.brand,
    s.total_sales,
    s.sales_rank,
    p.purchase_count,
    p.purchase_rank
FROM
    sales_ranking s
JOIN
    purchase_ranking p
ON
    s.brand = p.brand
ORDER BY
    s.sales_rank;
        
