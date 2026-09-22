CLASS zcl_http_test DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    " Structure of one product received from Northwind OData
    TYPES:
      BEGIN OF ty_product,
        productid       TYPE i,
        productname     TYPE string,
        supplierid      TYPE i,
        categoryid      TYPE i,
        quantityperunit TYPE string,
        unitprice       TYPE decfloat34,
        unitsinstock    TYPE i,
        unitsonorder    TYPE i,
        reorderlevel    TYPE i,
        discontinued    TYPE abap_bool,
      END OF ty_product.

    " Internal table containing products
    TYPES tt_products TYPE STANDARD TABLE OF ty_product WITH EMPTY KEY.

    " Structure of one OData response page.
    " VALUE contains business data.
    " NEXTLINK contains the URL of the next page, if another page exists.
    TYPES:
      BEGIN OF ty_response,
        value    TYPE tt_products,
        nextlink TYPE string,
      END OF ty_response.

    " Allows the class to be executed directly from ADT
    INTERFACES if_oo_adt_classrun.

ENDCLASS.


CLASS zcl_http_test IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    " Base URL of the Northwind OData V4 service
    DATA(lv_base_url) =
      'https://services.odata.org/V4/Northwind/Northwind.svc/'.

    " URL of the page currently being requested
    DATA(lv_request_url) =
      |{ lv_base_url }Products|.

    " Response structure for one OData page
    DATA ls_response TYPE ty_response.

    " Accumulates products received from all pages
    DATA lt_all_products TYPE tt_products.

    TRY.

        " Read OData pages until the service stops returning @odata.nextLink
        WHILE lv_request_url IS NOT INITIAL.

          " Create HTTP destination for the current page
          DATA(lo_destination) =
            cl_http_destination_provider=>create_by_url(
              i_url = lv_request_url
            ).

          " Create HTTP client using the destination
          DATA(lo_http_client) =
            cl_web_http_client_manager=>create_by_http_destination(
              lo_destination
            ).

          " Execute HTTP GET request
          DATA(lo_response) =
            lo_http_client->execute(
              i_method = if_web_http_client=>get
            ).

          " Read HTTP status and JSON response body
          DATA(ls_status) = lo_response->get_status( ).
          DATA(lv_body)   = lo_response->get_text( ).

          " Clear data from the previous OData page
          CLEAR ls_response.

          " Convert JSON response into ABAP structures.
          " @odata.nextLink is mapped explicitly because its JSON name
          " cannot be used directly as an ABAP component name.
          /ui2/cl_json=>deserialize(
            EXPORTING
              json = lv_body
              name_mappings = VALUE #(
                ( abap = 'NEXTLINK'
                  json = '@odata.nextLink' )
              )
            CHANGING
              data = ls_response
          ).

          " Add products from the current page to the complete result
          APPEND LINES OF ls_response-value TO lt_all_products.

          " Technical information about the current page
          out->write(
            |Requested: { lv_request_url }|
          ).

          out->write(
            |HTTP Status: { ls_status-code } { ls_status-reason }|
          ).

          out->write(
            |Products received: { lines( ls_response-value ) }|
          ).

          out->write(
            |Next link: { ls_response-nextlink }|
          ).

          " Prepare URL for the next OData page.
          " An empty NEXTLINK means that the last page has been reached.
          IF ls_response-nextlink IS INITIAL.

            CLEAR lv_request_url.

          ELSE.

            lv_request_url =
              |{ lv_base_url }{ ls_response-nextlink }|.

          ENDIF.

        ENDWHILE.

        " Show total number of products collected from all OData pages
        out->write(
          |Total products received: { lines( lt_all_products ) }|
        ).

        " Show selected fields from the complete product table
        LOOP AT lt_all_products INTO DATA(ls_product).

          out->write(
            |{ ls_product-productid } - { ls_product-productname } - { ls_product-unitprice }|
          ).

        ENDLOOP.

      " Catch errors in HTTP communication, destination creation
      " or JSON processing
      CATCH cx_root INTO DATA(lx_error).

        out->write(
          |Error: { lx_error->get_text( ) }|
        ).

    ENDTRY.

  ENDMETHOD.

ENDCLASS.
