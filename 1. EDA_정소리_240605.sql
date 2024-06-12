-- 중복값이 있어서 삭제하는 것 먼저 진행
CREATE TEMPORARY TABLE raw AS 
	SELECT DISTINCT event_time, event_type, product_id, brand, price, user_id, user_session
	FROM 2019dec;

CREATE TEMPORARY TABLE vt AS 
	SELECT user_id, user_session, event_time, category_id, product_id, brand, price
	FROM 2019dec
	WHERE event_type = 'view';
CREATE TEMPORARY TABLE ct AS 
	SELECT user_id, user_session, event_time, category_id, product_id, brand, price
	FROM 2019dec
	WHERE event_type = 'cart';
CREATE TEMPORARY TABLE pt AS 
	SELECT user_id, user_session, event_time, category_id, product_id, brand, price
	FROM 2019dec
	WHERE event_type = 'purchase';
CREATE TEMPORARY TABLE rt AS 
	SELECT user_id, user_session, event_time, category_id, product_id, brand, price
	FROM 2019dec
	WHERE event_type = 'remove_from_cart';
CREATE TEMPORARY TABLE v_to_c AS  -- 같은 아이디, 같은 세션, 같은 제품에 대해서 view 후 cart에 넣은 데이터들을 추출하는 테이블
	SELECT vt.*
		, ct.event_time AS cart_event_time
		, TIMESTAMPDIFF(SECOND, vt.event_time, ct.event_time) AS time_gap
	FROM vt
	LEFT JOIN ct ON vt.user_id = ct.user_id  -- left join 매칭으로 갯수가 더 커지는 이슈 있음
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
SELECT COUNT(DISTINCT event_time, event_type, category_id, category_code, product_id, brand, price, user_id, user_session)
FROM 2019dec_2;

#중복값을 확인한다.
SELECT event_time, event_type, category_id, category_code, product_id, brand, price, user_id, user_session, COUNT(*)
FROM 2019dec
GROUP BY event_time, event_type, category_id, category_code, product_id, brand, price, user_id, user_session
HAVING COUNT(*) > 1;

#중복값 펼쳐보기
SELECT *
FROM 2019dec
WHERE (event_time, event_type, category_id, product_id, brand, price, user_id, user_session) IN (
    SELECT event_time, event_type, category_id, product_id, brand, price, user_id, user_session
    FROM 2019dec
    GROUP BY event_time, event_type, category_id, product_id, brand, price, user_id, user_session
    HAVING COUNT(*) > 1
);

-- ------------------------------------------------------------------------------------------
#판매상품 평균 가격 확인 - 7.48달러
SELECT ROUND(AVG(price),2) AS avg_price
FROM (
	SELECT DISTINCT product_id, price
	FROM 2019dec
) a;

#입점 브랜드 수 : 253개
SELECT COUNT(DISTINCT brand)
FROM 2019dec;

#주차별 구매 세션 수, 구매 상품 개수, 총 판매금액 확인
WITH weekly AS(
	SELECT *
		, DATE_FORMAT(event_time, '%Y-%m-%d') AS event_date
		, WEEK(DATE_FORMAT(event_time, '%Y-%m-%d')) AS week -- 주차 계산
	FROM 2019dec
)
SELECT week
	, COUNT(product_id) AS product_cnt
	, COUNT(DISTINCT user_id, user_session) AS session_cnt
    , SUM(price) AS weekly_sales
FROM weekly
WHERE event_type = 'purchase'
GROUP BY week
ORDER BY week;

#가장 많이 판매된 product_id 추출 : product_id '5809910', session_cnt '1644'
SELECT product_id
	, COUNT(DISTINCT user_id, user_session) AS session_cnt
FROM 2019dec
WHERE event_type = 'purchase'
GROUP BY product_id
ORDER BY session_cnt DESC
LIMIT 1 ;

-- -----------------------------------------------------------------------
-- 리텐션 확인

SELECT *
FROM v_to_c
LIMIT 10;

#19년도 12월의 상황을 진단하고, 카트에서 물건을 빼는 현상을 포착하고 이 문제에 대해서 좀더 자세히 진단하고 싶다
#그래서 현상을 파악하고 카트에서 제외하는 비율을 좀 줄이고 싶다.

#12월 전체 들어온 view 유효 로그는 얼마만큼인가? - 794471
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

-- -----------------------------------------------------------------------
-- 카트에서 구매로 이어지는 비율 < remove_from_cart 비율이 훨씬 높은데 원인을 파악하고 액션 제안하기

#어떤 제품에서 카트 제거가 많이 이루어졌을까? 몇 차례나?
SELECT product_id, brand, price, category_id, COUNT(product_id) AS count
FROM c_to_r
GROUP BY product_id, brand, price, category_id
ORDER BY COUNT(product_id) DESC;

#보고 카트에 넣을 때 어떤 제품을 많이 담았는가 
-- left join으로 같은 유저, 같은 세션이라고 해도 제품에 따라 나누어져있는 테이블이 v_to_c이니 해당 테이블을 사용한다.
SELECT product_id, brand, price, category_id, COUNT(product_id) AS count
FROM v_to_c
GROUP BY product_id, brand, price, category_id
ORDER BY COUNT(product_id) DESC;

#제품별 카트제거 되는 비율을 살펴보자. 인기가 많아서 그만큼 많이 제거하는 것일 수 있음
WITH cart_count AS (
	SELECT product_id, brand, price, COUNT(product_id) count
	FROM v_to_c
    GROUP BY product_id, brand, price
), remove_count AS (
	SELECT product_id, brand, price, COUNT(product_id) count
	FROM c_to_r
    GROUP BY product_id, brand, price
)

SELECT cc.product_id, cc.brand, cc.price
    , rc.count AS remove_counts
    , cc.count AS cart_counts
    , COALESCE(rc.count, 0) / cc.count AS ratio
FROM remove_count rc
INNER JOIN cart_count cc ON rc.product_id = cc.product_id
    AND rc.brand = cc.brand
    AND rc.price = cc.price
ORDER BY cc.count DESC;

-- remove_counts에는 있지만 cart_counts랑 없는 경우가 있음. 이러한 경우는 다른 달의 영향도 있을 것 같아서 일단 제외하고 진행
-- left join 대신 inner join으로 변경
-- 비율이 36이 넘는 것이 있는데, 이전 달에 카트에 넣어놓았는지에 따라 갯수가 달라질 수 있을 것이라 판단하여, 이상치로 볼 것인지 결정이 필요

SELECT count(user_id)
FROM ct
LIMIT 10;

 -- 각 브랜드 별 구매 총 매출 및 물건을 구매한 횟수 집계 
SELECT brand
	, SUM(price) AS total_sales
	, COUNT(DISTINCT user_id) AS purchase_count
FROM 2019dec
WHERE event_type = 'purchase'
GROUP BY brand;
-- -----------------------------------------------------------------------
-- 카트에서 구매로 이어지는 비율 < remove_from_cart 비율이 훨씬 높은데 원인을 파악하고 액션 제안하기

#반품 비율이 높은 브랜드 뽑아내기
-- 테이블 세팅
CREATE TEMPORARY TABLE table_cart_count AS 
	SELECT product_id, brand, category_id, price, COUNT(product_id) count
	FROM v_to_c
    GROUP BY product_id, brand, price, category_id;
    
CREATE TEMPORARY TABLE table_remove_count AS 
	SELECT product_id, brand, category_id, price, COUNT(product_id) count
	FROM c_to_r
    GROUP BY product_id, brand, price, category_id;

CREATE TEMPORARY TABLE table_counts AS 
	SELECT cc.product_id, cc.brand, cc.price, cc.category_id
		, rc.count AS remove_counts
		, cc.count AS cart_counts
		, COALESCE(rc.count, 0) / cc.count AS ratio
	FROM table_remove_count rc
	INNER JOIN table_cart_count cc ON rc.product_id = cc.product_id
		AND rc.brand = cc.brand
		AND rc.price = cc.price
	ORDER BY cc.count DESC;

#반품 비율이 높은 브랜드 뽑아내기
SELECT brand, count(brand), AVG(price), AVG(ratio), AVG(cart_counts), AVG(remove_counts)
FROM table_counts
GROUP BY brand
HAVING count(brand) > 1  #1번 이상 반품이 일어났고, 비율이 0.8 이상인 경우만 뽑아보기
	AND AVG(ratio) > 0.8
ORDER BY count(brand) DESC;  -- 73개 브랜드가 나옴

#브랜드별로 제품을 보자
-- irisk : 1을 넘은 값들이 매우 많다. 전에 프로모션을 한 이력이 있는가? 무엇이 불만족스럽기에 카트에서 뺐을까?
SELECT *
FROM table_counts
WHERE brand = 'irisk'
ORDER BY ratio DESC;

-- runail
SELECT *
FROM table_counts
WHERE brand = 'runail'
ORDER BY ratio DESC;

-- masura
SELECT *
FROM table_counts
WHERE brand = 'masura'
ORDER BY ratio DESC;

#어떤 product_id 많을까?
SELECT product_id, brand, count(product_id) AS count
FROM table_counts
GROUP BY product_id, brand
ORDER BY count DESC;


#어떤 category_id가 많을까?
SELECT category_id, brand, count(category_id)
FROM table_counts
GROUP BY category_id, brand;


#다른 걸로 돌아와서
#어떤 아이디가 카트 제거를 많이했을까? 몇 차례나? - 동일한 걸 여러 번 했을 수도 있으니까 DISTINCT를 사용하지 않음
SELECT user_id, COUNT(product_id)
FROM c_to_r
GROUP BY user_id
ORDER BY COUNT(product_id) DESC;

#카트제거가 많았던 제품과 유저의 연관관계가 있을까?

SELECT * -- 테이블 내용 확인하고 싶을 때
FROM 2019dec
LIMIT 20;


-- -----------------------------------------------------------------------
-- 불필요
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
        
