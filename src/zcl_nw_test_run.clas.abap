CLASS zcl_nw_test_run DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    " Test runner for preparing controlled snapshot differences
    INTERFACES if_oo_adt_classrun.

ENDCLASS.


CLASS zcl_nw_test_run IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    TRY.

        " Simulate CHANGED:
        " Product 1 exists in both snapshots, but has a different price
""        UPDATE znw_acq_product
 ""         SET unit_price = 999
 ""         WHERE product_id = 1.



        " Simulate NEW:
        " Product 2 still exists in Northwind, but is missing
        " from the persisted snapshot
 ""      DELETE FROM znw_acq_product
 ""        WHERE product_id = 2.

        " Simulate DELETED:
        " Product 999 exists in the persisted snapshot,
        " but does not exist in Northwind
 """"         VALUE #(
 """"           client       = sy-mandt
 ""           product_id   = 999
""            product_name = 'Test Deleted Product'
 ""           unit_price   = 1
 ""         )
 ""       ).

  ""      COMMIT WORK AND WAIT.

  ""      out->write(
 ""         'Snapshot comparison test data prepared.'
  """"      ).

 """"       ROLLBACK WORK.

 ""       out->write(
 ""         |Error: { lx_error->get_text( ) }|
 ""       ).
        " TEST ONLY:
        " Repair acquisition state created by the previous
        " version of reconciliation logic.

""        ).
     " TEST ONLY:
        " Repair acquisition state created by the previous
        " version of reconciliation logic.
        UPDATE znw_acq_state
          SET status        = 'DONE',
              active_run_id = ''
          WHERE source_name = 'NORTHWIND_PRODUCTS'.


        IF sy-dbcnt = 1.

          COMMIT WORK AND WAIT.
        " For test ONLY
        " DELETE FROM znw_acq_state.
        " COMMIT WORK AND WAIT.

          out->write(
            'Acquisition state repaired.'
          ).

        ELSE.

          ROLLBACK WORK.

          out->write(
            |State repair failed. Rows affected: { sy-dbcnt }|
          ).

        ENDIF.

      CATCH cx_sy_open_sql_db INTO DATA(lx_db_error).

        ROLLBACK WORK.

        out->write(
          |Database error: { lx_db_error->get_text( ) }|
        ).

    ENDTRY.

  ENDMETHOD.

ENDCLASS.
