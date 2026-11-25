-- Uber Eats and Grubhub Restaurant Timing Irregularities (Google BigQuery)
-- Extracted from SQL_operations.pdf for direct browsing and syntax highlighting.

-- 1. Preview source tables
SELECT * FROM `arboreal-vision-339901.take_home_v2.virtual_kitchen_ubereats_hours` LIMIT 1000;
SELECT * FROM `arboreal-vision-339901.take_home_v2.virtual_kitchen_grubhub_hours` LIMIT 1000;

-- 2. Deduplicate by keeping only the most recent timestamp per slug
SELECT t1.response, t1.timestamp, t1.slug, t1.b_name, t1.vb_name, t1.vb_platform, t1.vb_address, t1.token
FROM `ordinal-link-390505.dataset.grubhub_initial` AS t1
INNER JOIN (
    SELECT slug, MAX(timestamp) AS max_timestamp
    FROM `ordinal-link-390505.dataset.grubhub_initial`
    GROUP BY slug
) t2
    ON t1.slug = t2.slug AND t1.timestamp = t2.max_timestamp;

SELECT u1.response, u1.timestamp, u1.slug, u1.b_name, u1.vb_name, u1.vb_platform, u1.vb_address, u1.token
FROM `ordinal-link-390505.dataset.ubereats_initial` AS u1
INNER JOIN (
    SELECT slug, MAX(timestamp) AS max_timestamp
    FROM `ordinal-link-390505.dataset.ubereats_initial`
    GROUP BY slug
) u2
    ON u1.slug = u2.slug AND u1.timestamp = u2.max_timestamp;

-- 3. Extract schedule rules JSON from Grubhub
CREATE TEMP FUNCTION JSON_Parser(jsonString STRING)
RETURNS STRUCT<days_of_week ARRAY<STRING>, from_time STRING, to_time STRING>
LANGUAGE js AS """
let parsed = JSON.parse(jsonString);
return {
    days_of_week: parsed.days_of_week,
    from_time: parsed.from,
    to_time: parsed.to
};
""";

WITH Table1 AS (
    SELECT tree, slug, CONCAT(b_name, ' ', vb_name) AS Business
    FROM `ordinal-link-390505.dataset.grubhub_initial_2` AS gh
    CROSS JOIN UNNEST(JSON_QUERY_ARRAY(gh.response, '$.availability_by_catalog.STANDARD_DELIVERY.schedule_rules')) AS tree
)
SELECT JSON_Parser(TO_JSON_STRING(tree)).*, Business
FROM Table1;

-- 4. Extract variable menu keys from Uber Eats JSON
CREATE TEMP FUNCTION EXTRACT_KV_PAIRS(json_str STRING)
RETURNS ARRAY<STRUCT<key STRING, value STRING>>
LANGUAGE js AS """
try {
    const json_dict = JSON.parse(json_str);
    return Object.entries(json_dict).map(
        (r) => Object.fromEntries([["key", r[0]], ["value", JSON.stringify(r[1])]])
    );
} catch (e) {
    return [{"key": "error", "value": String(e)}];
}
""";

SELECT EXTRACT_KV_PAIRS(TO_JSON_STRING(response.data.menus)), slug
FROM `silicon-alpha-390017.loop_assignment.ubereats`;

-- 5. Extract day of week, opening, and closing times for Uber Eats
WITH regularHours AS (
    SELECT
        JSON_QUERY_ARRAY(ujk.f0_[SAFE_OFFSET(0)].value, '$.sections.0.regularHours') AS regularHoursArray,
        ujk.slug,
        CONCAT(ue.b_name, ' ', ue.vb_name) AS name
    FROM `ordinal-link-390505.dataset.ubereats_initial_3_var` AS ujk
    JOIN `ordinal-link-390505.dataset.ubereats_initial_2` AS ue
        ON ujk.slug = ue.slug
),
regularHoursUnnested AS (
    SELECT
        JSON_QUERY(regularHour, '$.daysBitArray') AS daysBitArray,
        JSON_EXTRACT_SCALAR(regularHour, '$.endTime') AS endTime,
        JSON_EXTRACT_SCALAR(regularHour, '$.startTime') AS startTime,
        slug,
        name
    FROM regularHours
    CROSS JOIN UNNEST(regularHoursArray) AS regularHour
)
SELECT
    CASE
        WHEN daysBitArray = '[true,false,false,false,false,false,false]' THEN 'Sunday'
        WHEN daysBitArray = '[false,true,false,false,false,false,false]' THEN 'Monday'
        WHEN daysBitArray = '[false,false,true,false,false,false,false]' THEN 'Tuesday'
        WHEN daysBitArray = '[false,false,false,true,false,false,false]' THEN 'Wednesday'
        WHEN daysBitArray = '[false,false,false,false,true,false,false]' THEN 'Thursday'
        WHEN daysBitArray = '[false,false,false,false,false,true,false]' THEN 'Friday'
        WHEN daysBitArray = '[false,false,false,false,false,false,true]' THEN 'Saturday'
        ELSE 'Unknown'
    END AS dayOfWeek,
    startTime,
    endTime,
    name,
    slug
FROM regularHoursUnnested
ORDER BY name, CASE dayOfWeek
    WHEN 'Monday' THEN 1
    WHEN 'Tuesday' THEN 2
    WHEN 'Wednesday' THEN 3
    WHEN 'Thursday' THEN 4
    WHEN 'Friday' THEN 5
    WHEN 'Saturday' THEN 6
    WHEN 'Sunday' THEN 7
    ELSE 8
END;

-- 6. Unnest day of week in Grubhub table
CREATE TABLE `ordinal-link-390505.dataset.grubhub_initial_4` AS
SELECT
    (SELECT * FROM UNNEST(days_of_week) LIMIT 1) AS days_of_week,
    from_time,
    to_time,
    Business,
    slug
FROM `dataset.grubhub_initial_3`;

-- 7. Parse string times into TIME dtype
CREATE TABLE `ordinal-link-390505.dataset.ubereats_initial_4_time` AS
SELECT
    dayOfWeek,
    PARSE_TIME('%R', startTime) AS startTime,
    PARSE_TIME('%R', endTime) AS endTime,
    name,
    slug
FROM `ordinal-link-390505.dataset.ubereats_initial_4`
ORDER BY name;

CREATE TABLE `ordinal-link-390505.dataset.grubhub_initial_4_time` AS
SELECT
    days_of_week,
    PARSE_TIME('%T', SUBSTR(from_time, 1, 8)) AS from_time,
    PARSE_TIME('%T', SUBSTR(to_time, 1, 8)) AS to_time,
    Business AS name,
    slug
FROM `ordinal-link-390505.dataset.grubhub_initial_4`
ORDER BY name;

-- 8. Normalize dayOfWeek to lowercase
CREATE TABLE `ordinal-link-390505.dataset.grubhub_initial_5` AS
SELECT LOWER(days_of_week) AS dayOfWeek, from_time, to_time, name, slug
FROM `ordinal-link-390505.dataset.grubhub_initial_4_time`;

CREATE TABLE `ordinal-link-390505.dataset.ubereats_initial_5` AS
SELECT LOWER(dayOfWeek) AS dayOfWeek, startTime AS from_time, endTime AS to_time, name, slug
FROM `ordinal-link-390505.dataset.ubereats_initial_4_time`;

-- 9. Calculate operating minutes and compare matched businesses
SELECT
    gh.slug AS Grubhub_Slug,
    gh.from_time,
    gh.to_time,
    TIME_DIFF(gh.to_time, gh.from_time, MINUTE) + CASE
        WHEN gh.to_time = TIME '00:00:00' THEN 1440
        WHEN gh.from_time > TIME '12:00:00' AND gh.from_time > gh.to_time THEN 1440
        WHEN gh.from_time > gh.to_time THEN 720
        ELSE 0
    END AS GH_operating,
    ue.slug AS Ubereats_Slug,
    ue.from_time,
    ue.to_time,
    TIME_DIFF(ue.to_time, ue.from_time, MINUTE) + CASE
        WHEN ue.to_time = TIME '00:00:00' THEN 1440
        WHEN ue.from_time > TIME '12:00:00' AND ue.from_time > ue.to_time THEN 1440
        WHEN ue.from_time > ue.to_time THEN 720
        ELSE 0
    END AS UE_operating
FROM `ordinal-link-390505.dataset.ubereats_initial_5` AS ue
INNER JOIN `ordinal-link-390505.dataset.grubhub_initial_5` AS gh
    ON ue.name = gh.name AND ue.dayOfWeek = gh.dayOfWeek
ORDER BY ue.name;

-- 10. Classify timing discrepancies
SELECT
    Ubereats_Slug,
    UE_operating,
    Grubhub_Slug,
    GH_operating,
    CASE
        WHEN from_time_1 = from_time AND to_time_1 = to_time THEN 'In Range'
        WHEN (from_time_1 = from_time OR to_time_1 = to_time) AND ABS(GH_operating - UE_operating) < 5 THEN 'Out of range with 5 mins difference'
        WHEN (from_time_1 != from_time OR to_time_1 != to_time) AND ABS(GH_operating - UE_operating) >= 5 THEN 'Out of Range'
        ELSE NULL
    END AS In_Range
FROM `ordinal-link-390505.dataset.final_table`;
