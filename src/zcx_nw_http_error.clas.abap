CLASS zcx_nw_http_error DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC
    INHERITING FROM cx_static_check.

  PUBLIC SECTION.

    DATA status_code TYPE i READ-ONLY.
    DATA reason      TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING
        iv_status_code TYPE i
        iv_reason      TYPE string.

ENDCLASS.


CLASS zcx_nw_http_error IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.

    super->constructor( ).

    status_code = iv_status_code.
    reason      = iv_reason.

  ENDMETHOD.

ENDCLASS.
