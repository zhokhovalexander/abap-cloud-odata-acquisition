CLASS zcl_nw_acquisition DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.


  PUBLIC SECTION.

  " Candidates for retry
  TYPES:
  BEGIN OF ty_retry_candidate,
    run_id          TYPE znw_acq_run_log-run_id,
    original_run_id TYPE znw_acq_run_log-original_run_id,
    source_name     TYPE znw_acq_run_log-source_name,
    retry_count     TYPE znw_acq_run_log-retry_count,
  END OF ty_retry_candidate.

  TYPES tt_retry_candidates
    TYPE STANDARD TABLE OF ty_retry_candidate
    WITH EMPTY KEY.



  " Execute full acquisition of Northwind Product
  " Full snapshot replacement.
  " Reads all Products and completely replaces the persisted snapshot.
  " Simple reference implementation using DELETE + INSERT.
    METHODS full_load_replace
        RAISING
            zcx_nw_http_error
            zcx_nw_db_error.      .



  " Snapshot comparison.
  " Reads the complete source snapshot and compares it with persisted data.
  " Only detected inserts, updates and deletes are applied to the target.
  "
  " Note:
  " This is target-side change detection, not a source-side delta.
  " The complete Products entity set is still read from the OData source.
  " The approach reduces database changes, but not the API data volume.
  METHODS full_load_compare
    IMPORTING
            iv_original_run_id TYPE znw_acq_run_log-original_run_id OPTIONAL
            iv_retry_count     TYPE znw_acq_run_log-retry_count OPTIONAL
    RAISING
            zcx_nw_http_error
            zcx_nw_db_error
            zcx_nw_run_active
            zcx_nw_run_not_allowed.


  METHODS reconcile_runs
        RETURNING
            VALUE(rt_retry_candidates) TYPE tt_retry_candidates
        RAISING
            zcx_nw_db_error.


PRIVATE SECTION.

    CONSTANTS

 " Maximum number of automatic retries for a stale acquisition run
        c_max_retry_count TYPE i VALUE 3.



ENDCLASS.



CLASS ZCL_NW_ACQUISITION IMPLEMENTATION.


  METHOD full_load_replace.

    " Create OData client
    DATA(lo_odata_client) =
      NEW zcl_nw_odata_client( ).

    " Read complete Products entity set from Northwind
    DATA(lt_products) =
      lo_odata_client->get_products( ).

  "Snapshot is empty: acquisition layer reflects the source as received;
  " preservation and accumulation belong to downstream warehouse layers.
  "  IF lt_products IS INITIAL.
  "    RETURN.
  "  ENDIF.

    DATA lt_db_products TYPE STANDARD TABLE OF znw_acq_product
                        WITH EMPTY KEY.

    " Persistence logic will be added here
    LOOP AT lt_products INTO DATA(ls_product).

    APPEND VALUE #(
        client       = sy-mandt             " This field MUST NOT by empty
        product_id   = ls_product-productid
        product_name = ls_product-productname
        unit_price   = ls_product-unitprice
        ) TO lt_db_products.

    ENDLOOP.

    TRY.

" Replace current snapshot with the newly acquired data
    DELETE FROM znw_acq_product.

    INSERT znw_acq_product FROM TABLE @lt_db_products.

 " Update acquisition state in the same LUW
    DATA ls_state TYPE znw_acq_state.

    ls_state-client          = sy-mandt.
    ls_state-source_name     = 'NORTHWIND_PRODUCTS'.
    ls_state-load_type       = 'REPLACE'.
    ls_state-status          = 'DONE'.
    ls_state-last_success_at = utclong_current( ).
    ls_state-row_count       = lines( lt_products ).

    MODIFY znw_acq_state FROM @ls_state.


 " Commit business data and acquisition state together
    COMMIT WORK AND WAIT.

    CATCH cx_sy_open_sql_db INTO DATA(lx_db_error).

    " Cancel all database changes of the current LUW
        ROLLBACK WORK.

    " Convert technical Open SQL exception
    " into project-specific database exception
        RAISE EXCEPTION TYPE zcx_nw_db_error
            EXPORTING iv_reason = lx_db_error->get_text( ).

    ENDTRY.
  ENDMETHOD.


  METHOD full_load_compare.



  " Hashed table for fast lookup by ProductID.
" CLIENT is not part of the internal table key because the Open SQL SELECT
" already returns data for the current client only.
" The internal table key is chosen according to the comparison algorithm
" and does not have to match the database primary key.
  TYPES tt_db_products_hashed
  TYPE HASHED TABLE OF znw_acq_product
  WITH UNIQUE KEY product_id.

  TYPES tt_products_hashed
  TYPE HASHED TABLE OF zcl_nw_odata_client=>ty_product
  WITH UNIQUE KEY productid.


  DATA lv_new       TYPE i.
  DATA lv_changed   TYPE i.
  DATA lv_deleted   TYPE i.
  DATA lv_unchanged TYPE i.

  DATA i_break      TYPE i.

  DATA lt_db_products TYPE TABLE of znw_acq_product WITH KEY client product_id.

  DATA lt_db_products_hashed TYPE tt_db_products_hashed.

  DATA lt_products_hashed TYPE tt_products_hashed.






 " ID and starting time

DATA(lv_run_id) =
  cl_system_uuid=>create_uuid_c32_static( ).



DATA(lv_started_at) =
  utclong_current( ).

"Current state and log record
DATA ls_state   TYPE znw_acq_state.
DATA ls_run_log TYPE znw_acq_run_log.

ls_run_log-original_run_id  = iv_original_run_id.
ls_run_log-retry_count      = iv_retry_count.

" ---------------------------------------------------------
" Atomically acquire SOURCE_NAME for this RUN
" ---------------------------------------------------------

DATA lv_acquired TYPE abap_bool VALUE abap_false.

IF iv_retry_count = 0.

  " Normal run is allowed only after DONE or FAILED
  UPDATE znw_acq_state
    SET status        = 'RUNNING',
        active_run_id = @lv_run_id,
        load_type     = 'COMPARE'
    WHERE source_name = 'NORTHWIND_PRODUCTS'
      AND ( status = 'DONE'
         OR status = 'FAILED' ).

  IF sy-dbcnt = 1.

       lv_acquired = abap_true.

      ELSE.

    " No admissible existing state was updated.
    " It may be the very first run, so try to create the state.

        CLEAR ls_state.

        ls_state-client        = sy-mandt.
        ls_state-source_name   = 'NORTHWIND_PRODUCTS'.
        ls_state-load_type     = 'COMPARE'.
        ls_state-status        = 'RUNNING'.
        ls_state-active_run_id = lv_run_id.

        INSERT znw_acq_state FROM @ls_state.

    IF sy-subrc = 0.

       lv_acquired = abap_true.

    ELSE.
      " State already exists, but its current status
      " does not allow a normal run.
      " Handling will be added here.

    ENDIF.

  ENDIF.


ELSE.

  " Retry run is allowed only from STALE
  UPDATE znw_acq_state
    SET status        = 'RUNNING',
        active_run_id = @lv_run_id,
        load_type     = 'COMPARE'
    WHERE source_name = 'NORTHWIND_PRODUCTS'
      AND status      = 'STALE'.

  IF sy-dbcnt = 1.

     lv_acquired = abap_true.

  ELSE.

    " STALE state was not acquired.
    " Retry must not continue.
    " Handling will be added here.

  ENDIF.

ENDIF.

IF lv_acquired = abap_true.    "Capture is succesful
    SELECT SINGLE *
        FROM znw_acq_state
        WHERE source_name = 'NORTHWIND_PRODUCTS'
        INTO @ls_state.

     IF sy-subrc <> 0.
        ROLLBACK WORK.
    " Здесь позже можно поднять отдельное DB/state exception
            RETURN.
     ENDIF.

    ls_run_log-client      = sy-mandt.
    ls_run_log-run_id      = lv_run_id.
    ls_run_log-source_name = 'NORTHWIND_PRODUCTS'.
    ls_run_log-load_type   = 'COMPARE'.
    ls_run_log-status      = 'RUNNING'.
    ls_run_log-started_at  = lv_started_at.

    TRY.

        INSERT znw_acq_run_log FROM @ls_run_log.
        IF sy-subrc <> 0.

            ROLLBACK WORK.

            RAISE EXCEPTION TYPE zcx_nw_db_error
                EXPORTING
                iv_reason = 'Initial RUN_LOG record could not be created'.

        ENDIF.

        COMMIT WORK AND WAIT.
    CATCH cx_sy_open_sql_db INTO DATA(lx_start_db_error).
        ROLLBACK WORK.

        RAISE EXCEPTION TYPE zcx_nw_db_error
            EXPORTING
            iv_reason = lx_start_db_error->get_text( ).

    ENDTRY.
 ELSE.

  " Acquisition was not admitted.
  " Re-read the persisted state because ls_state may contain
  " values prepared for the failed INSERT attempt.
  CLEAR ls_state.

  SELECT SINGLE *
    FROM znw_acq_state
    WHERE source_name = 'NORTHWIND_PRODUCTS'
    INTO @ls_state.

  IF sy-subrc <> 0.

    RAISE EXCEPTION TYPE zcx_nw_db_error
      EXPORTING
        iv_reason =
          'Acquisition admission failed, but source state was not found'.

  ENDIF.

  IF ls_state-status = 'RUNNING'.

    RAISE EXCEPTION TYPE zcx_nw_run_active
      EXPORTING
        iv_active_run_id = ls_state-active_run_id
        iv_source_name   = ls_state-source_name.

  ELSE.

    DATA(lv_requested_mode) =
      COND zcx_nw_run_not_allowed=>ty_requested_mode(
        WHEN iv_retry_count = 0
          THEN 'NORMAL'
        ELSE
          'RETRY'
      ).

    RAISE EXCEPTION TYPE zcx_nw_run_not_allowed
      EXPORTING
        iv_source_name    = ls_state-source_name
        iv_state_status   = ls_state-status
        iv_requested_mode = lv_requested_mode.

  ENDIF.

 ENDIF.


"ls_state-last_success_at = CONV #( ls_state-last_success_at ).


" Read the complete current snapshot from the OData source
  DATA(lo_odata_client) =
    NEW zcl_nw_odata_client( ).


  TRY.

  DATA(lt_products) =
    lo_odata_client->get_products( ).

  CATCH zcx_nw_http_error INTO DATA(lx_http_error). "Processing HTTP error into get_product

    "Close operational state as FAILED
    ls_state-status = 'FAILED'.
    CLEAR ls_state-active_run_id.
    MODIFY znw_acq_state FROM @ls_state.

    "Close current run as FAILED
    ls_run_log-status      = 'FAILED'.
    ls_run_log-finished_at = utclong_current( ).
    ls_run_log-error_text  =
      |HTTP { lx_http_error->status_code }: { lx_http_error->reason }|.
    MODIFY znw_acq_run_log FROM @ls_run_log.
    COMMIT WORK AND WAIT.

    "Propagate original HTTP exception to the Runner
    RAISE EXCEPTION lx_http_error.

  ENDTRY.


  "Snapshot is empty: acquisition layer reflects the source as received;
  " preservation and accumulation belong to downstream warehouse layers.
 " IF lt_products IS INITIAL.
 "   RETURN.
 " ENDIF.

  lt_products_hashed =
  CORRESPONDING #( lt_products ).

"


  " Read the previously persisted snapshot
  SELECT *
    FROM znw_acq_product
    INTO TABLE @lt_db_products.
lt_db_products_hashed = CORRESPONDING #( lt_db_products ).

DATA lt_to_insert TYPE TABLE OF znw_acq_product.
DATA lt_to_update TYPE TABLE OF znw_acq_product.


LOOP AT lt_products INTO DATA(ls_product).

  READ TABLE lt_db_products_hashed
    WITH TABLE KEY product_id = ls_product-productid
    INTO DATA(ls_db_product).

  IF sy-subrc <> 0.

    APPEND VALUE #(
        client       = sy-mandt
        product_id   = ls_product-productid
        product_name = ls_product-productname
        unit_price   = ls_product-unitprice
    ) TO lt_to_insert.

    " Product exists in source but not in persisted snapshot
    lv_new += 1.

  ELSEIF
       ls_db_product-product_name <> ls_product-productname
    OR ls_db_product-unit_price   <> ls_product-unitprice.

    " Product exists in both snapshots, but business data has changed
    lv_changed += 1.

    APPEND VALUE #(
    client       = sy-mandt
    product_id   = ls_product-productid
    product_name = ls_product-productname
    unit_price   = ls_product-unitprice
    ) TO lt_to_update.

  ELSE.

    " Product exists in both snapshots and business data is unchanged
    lv_unchanged += 1.

  ENDIF.

ENDLOOP.

DATA lt_to_delete TYPE TABLE OF znw_acq_product.

LOOP AT lt_db_products INTO ls_db_product.

  READ TABLE lt_products_hashed
    WITH TABLE KEY productid = ls_db_product-product_id
    TRANSPORTING NO FIELDS.

  IF sy-subrc <> 0.

    " Product exists in persisted snapshot but no longer exists in source
    lv_deleted += 1.
    APPEND ls_db_product TO lt_to_delete.

  ENDIF.

ENDLOOP.

" Apply detected changes and acquisition state
" in one database transaction

"TRY for business data
TRY.

IF lt_to_insert IS NOT INITIAL.
  INSERT znw_acq_product FROM TABLE @lt_to_insert.

" TEST ONLY:
" Second INSERT must cause a duplicate-key database error
" INSERT znw_acq_product FROM TABLE @lt_to_insert.


ENDIF.

IF lt_to_update IS NOT INITIAL.
  MODIFY znw_acq_product FROM TABLE @lt_to_update.
ENDIF.

IF lt_to_delete IS NOT INITIAL.
  DELETE znw_acq_product FROM TABLE @lt_to_delete.
ENDIF.

" Update state of the successful acquisition

"DATA ls_state TYPE znw_acq_state.

ls_state-client          = sy-mandt.
ls_state-source_name     = 'NORTHWIND_PRODUCTS'.
ls_state-load_type       = 'COMPARE'.
ls_state-status          = 'DONE'.
ls_state-last_success_at = utclong_current( ).
ls_state-row_count       = lines( lt_products ).
CLEAR ls_state-active_run_id.

MODIFY znw_acq_state FROM @ls_state.

" Commit business data and acquisition state together

COMMIT WORK AND WAIT.

"CATCH for business data
CATCH cx_sy_open_sql_db INTO DATA(lx_db_error).

    " Cancel all database changes of the current LUW
    ROLLBACK WORK.

    "Update operational state after ROLLBACK
    ls_state-status = 'FAILED'.
    CLEAR ls_state-active_run_id.


    MODIFY znw_acq_state FROM @ls_state.


    "Update current RUN_LOG
    ls_run_log-status = 'FAILED'.
    ls_run_log-finished_at = utclong_current( ).
    ls_run_log-error_text = lx_db_error->get_text( ).

    MODIFY znw_acq_run_log FROM @ls_run_log.

    COMMIT WORK AND WAIT.

    " Convert technical Open SQL exception
    " into project-specific database exception
    RAISE EXCEPTION TYPE zcx_nw_db_error
        EXPORTING
            iv_reason = lx_db_error->get_text( ).


"ENDTRY for business data
ENDTRY.

"TRY for RUN log
" Update run log in a separate LUW

    TRY.
        ls_run_log-status       = 'DONE'.
        ls_run_log-finished_at  = utclong_current( ).
        ls_run_log-row_count    = lines( lt_products ).
        ls_run_log-new_count    = lv_new.
        ls_run_log-changed_count = lv_changed.
        ls_run_log-deleted_count = lv_deleted.

        MODIFY znw_acq_run_log FROM @ls_run_log.


        " TEST ONLY^ force duplicate-key DB error

            " TEST ONLY
 "              DATA lt_test_log TYPE TABLE OF znw_acq_run_log.
 "               APPEND ls_run_log TO lt_test_log.
 "               INSERT znw_acq_run_log FROM TABLE @lt_test_log.

        COMMIT WORK AND WAIT.

"CATCH for RUN log
    CATCH cx_sy_open_sql_db INTO DATA(lx_log_error).

 " Roll back only the logging transaction.
 " Business data and acquisition state were already committed.
        ROLLBACK WORK.

"ENDTRY for RUN log
    ENDTRY.
" Debug breakpoint
i_break = 0.

  ENDMETHOD.


 METHOD reconcile_runs.

"Find threshold
 DATA(lv_threshold) =
  utclong_add(
    val     = utclong_current( )
    minutes = -1                       " For test -15, for work -1
  ).

 DATA lt_running_runs TYPE TABLE OF znw_acq_run_log.

 SELECT *
  FROM znw_acq_run_log
  WHERE status     = 'RUNNING'
    AND started_at < @lv_threshold
  INTO TABLE @lt_running_runs.

  " Reconcilliation v1
  " Phase 1: classify old RUNNING records

  LOOP AT lt_running_runs INTO DATA(ls_run).

  SELECT SINGLE *
    FROM znw_acq_state
    WHERE source_name = @ls_run-source_name
    INTO @DATA(ls_state).

  IF sy-subrc = 0
     AND ls_state-status = 'RUNNING'
     AND ls_state-active_run_id = ls_run-run_id.


 " This run is still registered as the active run,
 " but it has exceeded the allowed runtime.
    ls_run-status = 'STALE'.

 " Release the source because this run is no longer considered active
    ls_state-status = 'STALE'.


" Do not clear ACTIVE_RUN_ID here.
" It identifies the STALE run awaiting retry.

      MODIFY znw_acq_run_log FROM @ls_run.
      MODIFY znw_acq_state FROM @ls_state.

 "Writing new candidate to RETRY into table
 "rt_retry_candidates - public table with data of retry processes
 "   IF ls_run-retry_count < c_max_retry_count.
 "       APPEND VALUE #(
 "               run_id          = ls_run-run_id
 "               original_run_id = ls_run-original_run_id
 "               source_name     = ls_run-source_name
 "               retry_count     = ls_run-retry_count
 "               ) TO rt_retry_candidates.


 "   ENDIF.

  ELSE.


" This run is no longer the active run,
" but its final status was not recorded reliably.
    ls_run-status = 'UNKNOWN'.
      MODIFY znw_acq_run_log FROM @ls_run.

  ENDIF.

ENDLOOP.

COMMIT WORK AND WAIT.

" Phase 2: process persisted STALE runs


SELECT SINGLE *
  FROM znw_acq_state
  WHERE source_name = 'NORTHWIND_PRODUCTS'
  INTO @DATA(ls_retry_state).

IF sy-subrc = 0
   AND ls_retry_state-status = 'STALE'
   AND ls_retry_state-active_run_id IS NOT INITIAL.


SELECT SINGLE *
  FROM znw_acq_run_log
  WHERE status = 'STALE'
  AND  run_id = @ls_retry_state-active_run_id
  INTO @DATA(ls_stale_run).

   IF sy-subrc = 0.

    IF ls_stale_run-retry_count < c_max_retry_count.

      APPEND VALUE #(
        run_id          = ls_stale_run-run_id
        original_run_id = ls_stale_run-original_run_id
        source_name     = ls_stale_run-source_name
        retry_count     = ls_stale_run-retry_count
      ) TO rt_retry_candidates.

    ELSE.

      ls_retry_state-status = 'RETRY_LIMIT'.
      CLEAR ls_retry_state-active_run_id.

      MODIFY znw_acq_state FROM @ls_retry_state.

      COMMIT WORK AND WAIT.

    ENDIF.

  ENDIF.

  ENDIF.

 ENDMETHOD.
ENDCLASS.
