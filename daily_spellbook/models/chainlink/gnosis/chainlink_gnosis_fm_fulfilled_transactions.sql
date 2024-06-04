{{
  config(

    alias='fm_fulfilled_transactions',
    partition_by=['date_month'],
    materialized='incremental',
    file_format='delta',
    incremental_strategy='merge',
    unique_key=['tx_hash', 'tx_index', 'node_address'],
    incremental_predicates = [incremental_predicate('DBT_INTERNAL_DEST.block_time')]
  )
}}


WITH
  gnosis_usd AS (
    SELECT
      minute as block_time,
      price as usd_amount
    FROM
      {{ source('prices', 'usd') }} price
    WHERE
      symbol = 'XDAI'
      {% if is_incremental() %}
        AND {{ incremental_predicate('minute') }}
      {% endif %}
  ),
  fm_submission_transactions AS (
    SELECT
      tx.hash as tx_hash,
      tx.index as tx_index,
      MAX(tx.block_time) as block_time,
      cast(date_trunc('month', MAX(tx.block_time)) as date) as date_month,
      tx."from" as "node_address",
      MAX(
        (cast((gas_used) as double) / 1e18) * gas_price
      ) as token_amount,
      MAX(gnosis_usd.usd_amount) as usd_amount
    FROM
      {{ source('gnosis', 'transactions') }} tx
      RIGHT JOIN {{ ref('chainlink_gnosis_fm_gas_submission_logs') }} fm_gas_submission_logs ON fm_gas_submission_logs.tx_hash = tx.hash
      {% if is_incremental() %}
        AND {{ incremental_predicate('fm_gas_submission_logs.block_time') }}
      {% endif %}
      LEFT JOIN gnosis_usd ON date_trunc('minute', tx.block_time) = gnosis_usd.block_time
    {% if is_incremental() %}
      WHERE {{ incremental_predicate('tx.block_time') }}
    {% endif %}
    GROUP BY
      tx.hash,
      tx.index,
      tx."from"
  )
SELECT
 'gnosis' as blockchain,
  block_time,
  date_month,
  node_address,
  token_amount,
  usd_amount,
  tx_hash,
  tx_index
FROM
  fm_submission_transactions