REPORT zcl_sics_apc_test.

PARAMETERS p_host  TYPE string LOWER CASE.
PARAMETERS p_port  TYPE string LOWER CASE.
PARAMETERS p_tls   TYPE abap_bool AS CHECKBOX DEFAULT abap_false.
PARAMETERS p_sslid TYPE if_abap_channel_types=>ty_ssfapplssl DEFAULT 'ANONYM'.

START-OF-SELECTION.
  TRY.
      DATA(lo_client) = NEW zcl_sics_apc(
        iv_host    = p_host
        iv_port    = p_port
        iv_use_tls = p_tls
        iv_ssl_id  = p_sslid ).

      lo_client->connect( ).

      DATA(lv_response) = lo_client->execute( `S` ).

      IF lv_response IS INITIAL.
        WRITE: / 'No response received.'.
      ELSE.
        WRITE: / lv_response.
      ENDIF.

      lo_client->disconnect( ).
    CATCH cx_apc_error INTO DATA(lx_apc_error).
      WRITE: / lx_apc_error->get_text( ).
  ENDTRY.
