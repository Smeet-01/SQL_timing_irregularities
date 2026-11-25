# Restaurant Timing Irregularities (BigQuery SQL)

An SQL workflow on **Google BigQuery** to detect opening and closing time discrepancies between restaurants listed on **Uber Eats** and **Grubhub**.

## Approach
1. Deduplicate raw platform snapshots by keeping the latest `timestamp` per `slug`.
2. Parse nested JSON schedule structures using BigQuery JavaScript UDFs (`JSON_Parser`, `EXTRACT_KV_PAIRS`).
3. Normalize weekday names and convert string timestamps to `TIME`.
4. Join matched restaurants by business name and weekday, compute operating duration in minutes, and classify discrepancies (`In Range`, `Out of range with 5 mins difference`, `Out of Range`).

## Files
- `SQL_operations.sql`: Full BigQuery SQL & JS UDF queries.
- `SQL_operations.pdf`: Original PDF export of the queries and notes.
