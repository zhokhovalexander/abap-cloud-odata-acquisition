CLASS zcx_nw_db_error DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC
  INHERITING FROM cx_static_check.

  PUBLIC SECTION.

    DATA reason TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING
        iv_reason TYPE string.

ENDCLASS.


CLASS zcx_nw_db_error IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.

    super->constructor( ).

    reason = iv_reason.

  ENDMETHOD.

ENDCLASS..
