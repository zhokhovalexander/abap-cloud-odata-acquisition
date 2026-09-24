CLASS zcl_nw_run DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    " Allows direct execution from ADT
    INTERFACES if_oo_adt_classrun.

ENDCLASS.


CLASS zcl_nw_run IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    TRY.


        " Create acquisition process
        DATA(lo_acquisition) =
          NEW zcl_nw_acquisition( ).


        " Reconcile unfinished runs from previous  executions


        DATA lt_retry_candidates TYPE zcl_nw_acquisition=>tt_retry_candidates.

        lt_retry_candidates = lo_acquisition->reconcile_runs( ).                         " Comment for STALE - test

        IF lt_retry_candidates IS NOT INITIAL.
            LOOP AT lt_retry_candidates INTO DATA(ls_candidate).
                DATA(lv_original_run_id) =
                    COND znw_acq_run_log-original_run_id(
                        WHEN ls_candidate-original_run_id IS INITIAL
                        THEN ls_candidate-run_id
                        ELSE ls_candidate-original_run_id
                     ).

                lo_acquisition->full_load_compare(
                    iv_original_run_id = lv_original_run_id
                    iv_retry_count = ls_candidate-retry_count + 1
                ).

            ENDLOOP.
        ELSE.
        " Execute full load from Northwind into persistence table
"        lo_acquisition->full_load_replace( ).
"Before processing check znw_acq_state - status.
             SELECT SINGLE * FROM znw_acq_state
                WHERE source_name = 'NORTHWIND_PRODUCTS'
                INTO @DATA(ls_state).

             IF sy-subrc = 0 AND ls_state-status = 'RETRY_LIMIT'.

                out->write( |'Automatic retry limit reached. New acquisition run was not started| ).

             ELSE.

                lo_acquisition->full_load_compare( ).

             ENDIF.

        ENDIF.

        out->write(
          'Northwind Products full load completed.'
        ).



       CATCH zcx_nw_run_active INTO DATA(lx_run_active).
            "Expected run_active
         out->write(
            |Acquisition is already running for { lx_run_active->source_name }.|
            && | Active run ID: { lx_run_active->active_run_id  }|
          ).



        CATCH zcx_nw_run_not_allowed INTO DATA(lx_not_allowed).

        out->write(
            |Run not allowed for { lx_not_allowed->source_name }. |
            && |Current state: { lx_not_allowed->state_status }. |
            && |Requested mode: { lx_not_allowed->requested_mode }.|
        ).

       CATCH zcx_nw_http_error INTO DATA(lx_http_error).
            " Expected HTTP error raised by the HTTP client
         out->write(
            |HTTP Error:{ lx_http_error->status_code } { lx_http_error->reason }|
          ).

       CATCH zcx_nw_db_error INTO DATA(lx_db_error).
       "Expected db error raised by OpenSQL operation
            out->write(
            |DataBase error:{ lx_db_error->reason }|
             ).




       CATCH cx_root INTO DATA(lx_error).  " Общая ловушка ошибок
          " Fallback for unexpected exceptions
        out->write(
          |Error: { lx_error->get_text( ) }|
        ).

    ENDTRY.

  ENDMETHOD.

ENDCLASS.
