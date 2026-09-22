CLASS zcl_nw_odata_client DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

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

    TYPES tt_products TYPE STANDARD TABLE OF ty_product WITH EMPTY KEY.

    METHODS get_products
      RETURNING
        VALUE(rt_products) TYPE tt_products
      RAISING
        zcx_nw_http_error.

  PRIVATE SECTION.

    TYPES:
      BEGIN OF ty_response,
        value    TYPE tt_products,
        nextlink TYPE string,
      END OF ty_response.

ENDCLASS.


CLASS zcl_nw_odata_client IMPLEMENTATION.

  METHOD get_products.

    " Base URL of the Northwind OData V4 service
    DATA(lv_base_url) =
      'https://services.odata.org/V4/Northwind/Northwind.svc/'.

    " Expected error "Host name .... not found"
    " 'https://nonexistent.example.invalid/'. " Uncorrect HOST name: for TEST ONLY

    " OData projection: fields requested from the source
    DATA(lv_select) =
      '$select=ProductID,ProductName,UnitPrice'.

    " OData selection: restrict products at the source
    " Spaces are URL-encoded as %20
    "DATA(lv_filter) =
    "  '$filter=UnitPrice%20gt%2020'.

    " Initial request URL with OData query options
    DATA(lv_request_url) =
      |{ lv_base_url }Products?{ lv_select }|.

    " Expected error HTTP 404 Not found
    " |{ lv_base_url }ProductXXXX?{ lv_select }|. " HTTP error's generation for TEST ONLY!

    " |{ lv_base_url }Products?{ lv_select }&{ lv_filter }|.

    DATA ls_response TYPE ty_response.

    DATA(lo_http_client) =
      NEW zcl_nw_http_client( ).

    WHILE lv_request_url IS NOT INITIAL.

      " Get JSON for the current OData page
      DATA(lv_body) =
        lo_http_client->get(
          iv_url = lv_request_url
        ).

      CLEAR ls_response.

      " Deserialize business data and OData nextLink
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

      " Add current page to the complete result
      APPEND LINES OF ls_response-value TO rt_products.

      " Follow server-provided paging link
      IF ls_response-nextlink IS INITIAL.

        CLEAR lv_request_url.

      ELSE.

        lv_request_url =
          |{ lv_base_url }{ ls_response-nextlink }|.

      ENDIF.

    ENDWHILE.

  ENDMETHOD.

ENDCLASS.
