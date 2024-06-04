{{
  config(

    alias='vrf_reverted_transactions',
    partition_by=['date_month'],
    materialized='incremental',
    file_format='delta',
    incremental_strategy='merge',
    unique_key=['tx_hash', 'tx_index', 'node_address'],
    incremental_predicates = [incremental_predicate('DBT_INTERNAL_DEST.block_time')]
  )
}}


WITH
  arbitrum_usd AS (
    SELECT
      minute as block_time,
      price as usd_amount
    FROM
      {{ source('prices', 'usd') }} price
    WHERE
      symbol = 'ETH'
      {% if is_incremental() %}
        AND {{ incremental_predicate('minute') }}
      {% endif %}
  ),
  vrf_reverted_transactions AS (
    SELECT
      tx.hash as tx_hash,
      tx.index as tx_index,
      MAX(tx.block_time) as block_time,
      cast(date_trunc('month', MAX(tx.block_time)) as date) as date_month,
      tx."from" as "node_address",
      MAX(
        (cast((gas_used) as double) / 1e18) * effective_gas_price
      ) as token_amount,
      MAX(arbitrum_usd.usd_amount) as usd_amount
    FROM
      {{ source('arbitrum', 'transactions') }} tx
      LEFT JOIN arbitrum_usd ON date_trunc('minute', tx.block_time) = arbitrum_usd.block_time
    WHERE
      success = false
      {% if is_incremental() %}
        AND {{ incremental_predicate('tx.block_time') }}
      {% endif %}
    GROUP BY
      tx.hash,
      tx.index,
      tx."from"
  )
SELECT
 'arbitrum' as blockchain,
  block_time,
  date_month,
  node_address,
  token_amount,
  usd_amount,
  tx_hash,
  tx_index
FROM
  vrf_reverted_transactions