# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Pure SQL data modeling project (no build system). Models are written for **Snowflake** and organized in a dbt-inspired 4-layer architecture. The goal is to produce a weekly reporting dashboard for Lorette, head of the Skello Support team, based on Intercom conversation data.

Source tables: `CONVERSATIONS` and `CONVERSATION_PARTS` (raw data from Intercom via ETL, available as CSV files at the repo root).

## Running the models

Execute SQL files in Snowflake in dependency order:

```
1. models/0_seeds/dim_support_agents.sql       -- static reference table
2. models/1_staging/stg_conversations.sql      -- (parallel)
   models/1_staging/stg_conversation_parts.sql -- (parallel)
3. models/2_intermediate/int_first_responses.sql
   models/2_intermediate/int_conversation_metrics.sql  -- depends on dim_support_agents + both staging views
4. models/3_marts/mart_weekly_kpis.sql         -- (parallel)
   models/3_marts/mart_agent_weekly_performance.sql    -- (parallel)
   models/3_marts/mart_volume_heatmap.sql              -- (parallel)
```

Staging and intermediate layers are `VIEW`s. Mart layer is materialized as `TABLE` for BI tool performance.

## Architecture

```
RAW (Snowflake) ──► 0_seeds ──► 1_staging ──► 2_intermediate ──► 3_marts
```

- **0_seeds**: `dim_support_agents` — hardcoded reference mapping Intercom agent IDs to names. Update manually when team changes.
- **1_staging**: Parse JSON columns (`CONVERSATION_RATING`, `ASSIGNEE`, `AUTHOR`), cast types, add ISO week helpers. No business filters — all rows pass through.
- **2_intermediate**: Business logic lives here. `int_first_responses` identifies the first human admin reply per conversation and computes the SLA flag. `int_conversation_metrics` is the central enriched view (one row per conversation) joining staging + first response + support team flag.
- **3_marts**: Aggregations consumed directly by the BI tool. Three tables cover: weekly KPIs (header cards + trend charts), per-agent weekly performance, and volume heatmap (day × hour).

## Key conventions

**JSON parsing**: `CONVERSATION_RATING` and `ASSIGNEE` columns may be stored as JSON strings or as Snowflake `VARIANT`. The staging layer uses `TRY_PARSE_JSON()` + `TRY_CAST()` to handle both cases gracefully.

**`PART_GROUP` vs `PART_TYPE`**: The ETL delivers `PART_GROUP` (not `PART_TYPE` as documented). Use `PART_GROUP = 'Message'` to filter real messages; values `Assignment`, `Close`, `Quick Reply` are system events and must be excluded.

**Bot exclusion**: Always filter `author_type = 'admin'` when measuring SLA or response time. Bots (`author_type = 'bot'`) are explicitly excluded from all metrics.

**Support team scope**: Only conversations where `assignee_id IN (5217337, 5391224, 5440474, 5300290)` are counted as Support team work. The flag `is_support_team_conversation` in `int_conversation_metrics` carries this.

**SLA denominator**: `pct_sla_met` divides by `COUNT(CASE WHEN has_admin_reply THEN 1 END)` — not total conversations — to avoid penalizing unanswered conversations.

**Timestamps**: All timestamps are UTC. A `CONVERT_TIMEZONE('Europe/Paris', ...)` transform is needed before the heatmap day/hour groupings are meaningful in French local time (not yet applied — flagged as open question for Lorette).

**Median over mean**: First response time uses `MEDIAN()` as the primary KPI; `AVG()` is computed alongside but is heavily skewed by overnight/weekend conversations.
