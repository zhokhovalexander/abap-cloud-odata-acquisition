CLASS zcx_nw_run_not_allowed DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES ty_requested_mode TYPE c LENGTH 6.

    DATA source_name
      TYPE znw_acq_state-source_name
      READ-ONLY.

    DATA state_status
      TYPE znw_acq_state-status
      READ-ONLY.

    DATA requested_mode
      TYPE c LENGTH 6
      READ-ONLY.

    METHODS constructor
      IMPORTING
        iv_source_name    TYPE znw_acq_state-source_name
        iv_state_status   TYPE znw_acq_state-status
        iv_requested_mode TYPE ty_requested_mode.

ENDCLASS.

CLASS zcx_nw_run_not_allowed IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.

    super->constructor( ).

    source_name    = iv_source_name.
    state_status   = iv_state_status.
    requested_mode = iv_requested_mode.

  ENDMETHOD.

ENDCLASS.
