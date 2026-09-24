CLASS zcl_nw_test_driver DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

ENDCLASS.


CLASS zcl_nw_test_driver IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    DATA(lo_acquisition) = NEW zcl_nw_acquisition( ).

    TRY.

" Full load compare
        lo_acquisition->full_load_compare(
        iv_original_run_id = '829C51E967C21FE1ADE7AC0CCA382369'
        iv_retry_count     = 1
         ).

        out->write(
          'Normal full_load_compare completed.'
        ).
"*****************************************************

" Reconcile runs
"  DATA(lt_candidates) =
"                 lo_acquisition->reconcile_runs( ).

"         out->write(
"                |Retry candidates: { lines( lt_candidates ) }|
"         ).
"****************************************************


      CATCH zcx_nw_run_active INTO DATA(lx_run_active).

        out->write(
          |Acquisition is already running for { lx_run_active->source_name }. |
          && |Active run ID: { lx_run_active->active_run_id }|
        ).


       CATCH zcx_nw_run_not_allowed INTO DATA(lx_not_allowed).

        out->write(
            |Run not allowed for { lx_not_allowed->source_name }. |
            && |Current state: { lx_not_allowed->state_status }. |
            && |Requested mode: { lx_not_allowed->requested_mode }.|
        ).

      CATCH zcx_nw_http_error INTO DATA(lx_http).

        out->write(
          |HTTP Error: { lx_http->status_code } { lx_http->reason }|
        ).

      CATCH zcx_nw_db_error INTO DATA(lx_db).

        out->write(
          |Database Error: { lx_db->reason }|
        ).

    ENDTRY.

  ENDMETHOD.

ENDCLASS.
