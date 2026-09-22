CLASS zcx_nw_run_active DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC
    INHERITING FROM cx_static_check.

  PUBLIC SECTION.

    DATA source_name   TYPE c LENGTH 40 READ-ONLY.
    DATA active_run_id TYPE c LENGTH 32 READ-ONLY.

    METHODS constructor
      IMPORTING
        iv_source_name   TYPE znw_acq_state-source_name
        iv_active_run_id TYPE znw_acq_state-active_run_id.

ENDCLASS.


CLASS zcx_nw_run_active IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.

    super->constructor( ).

    source_name   = iv_source_name.
    active_run_id = iv_active_run_id.

  ENDMETHOD.

ENDCLASS.
