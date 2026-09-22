CLASS zcl_nw_http_client DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    " Execute HTTP GET request and return response body
    METHODS get
      IMPORTING
        iv_url         TYPE string
      RETURNING
        VALUE(rv_body) TYPE string
      RAISING
        zcx_nw_http_error.

ENDCLASS.


CLASS zcl_nw_http_client IMPLEMENTATION.

  METHOD get.

    TRY.

        " Create HTTP destination for the requested URL
        DATA(lo_destination) =
          cl_http_destination_provider=>create_by_url(
            i_url = iv_url
          ).

        " Create HTTP client for the destination
        DATA(lo_http_client) =
          cl_web_http_client_manager=>create_by_http_destination(
            lo_destination
          ).

        " Execute HTTP GET request
        DATA(lo_response) =
          lo_http_client->execute(
            i_method = if_web_http_client=>get
          ).

        " Read HTTP status
        DATA(ls_status) = lo_response->get_status( ).

        " Current project scenario expects HTTP 200
        IF ls_status-code <> 200.

          RAISE EXCEPTION TYPE zcx_nw_http_error
            EXPORTING
              iv_status_code = ls_status-code
              iv_reason      = ls_status-reason.

        ENDIF.

        " Return HTTP response body
        rv_body = lo_response->get_text( ).

      CATCH cx_web_http_client_error INTO DATA(lx_web_error).

        RAISE EXCEPTION TYPE zcx_nw_http_error
          EXPORTING
            iv_status_code = 0
            iv_reason      = lx_web_error->get_text( ).

    ENDTRY.

  ENDMETHOD.

ENDCLASS.
