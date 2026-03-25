CLASS zcl_sics_apc DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_apc_wsp_event_handler.

    METHODS constructor
      IMPORTING
        !iv_host           TYPE string
        !iv_port           TYPE string
        !iv_use_tls        TYPE abap_bool DEFAULT abap_false
        !iv_ssl_id         TYPE if_abap_channel_types=>ty_ssfapplssl DEFAULT 'ANONYM'
        !iv_connect_timeout TYPE i DEFAULT 0
      RAISING
        cx_apc_error.
    METHODS connect
      RAISING
        cx_apc_error.
    METHODS disconnect
      IMPORTING
        !iv_reason TYPE string OPTIONAL
      RAISING
        cx_apc_error.
    METHODS send_command
      IMPORTING
        !iv_command TYPE string
      RAISING
        cx_apc_error.
    METHODS receive
      IMPORTING
        !iv_timeout_seconds TYPE decfloat34 DEFAULT '5'
      RETURNING
        VALUE(rv_response)  TYPE string.
    METHODS execute
      IMPORTING
        !iv_command         TYPE string
        !iv_timeout_seconds TYPE decfloat34 DEFAULT '5'
      RETURNING
        VALUE(rv_response)  TYPE string
      RAISING
        cx_apc_error.
    METHODS get_connection_id
      RETURNING
        VALUE(rv_connection_id) TYPE if_abap_channel_types=>ty_apc_connection_id
      RAISING
        cx_apc_error.
    METHODS is_connected
      RETURNING
        VALUE(rv_connected) TYPE abap_bool
      RAISING
        cx_apc_error.
    METHODS get_last_error
      RETURNING
        VALUE(rv_last_error) TYPE string.
    METHODS clear_messages.

  PRIVATE SECTION.
    DATA mv_host TYPE string.
    DATA mv_port TYPE string.
    DATA mv_protocol TYPE i.
    DATA mv_ssl_id TYPE if_abap_channel_types=>ty_ssfapplssl.
    DATA mv_connect_timeout TYPE i.
    DATA mv_last_error TYPE string.
    DATA mv_close_reason TYPE string.
    DATA mv_close_code TYPE i.
    DATA mv_is_open TYPE abap_bool.
    DATA mv_is_closed TYPE abap_bool.
    DATA mo_client TYPE REF TO if_apc_wsp_client.
    DATA mo_message_manager TYPE REF TO if_apc_wsp_message_manager.
    DATA mt_messages TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    METHODS build_frame
      RETURNING
        VALUE(rs_frame) TYPE if_abap_channel_types=>ty_apc_tcp_frame.
    METHODS create_client
      RAISING
        cx_apc_error.
    METHODS normalize_command
      IMPORTING
        !iv_command TYPE string
      RETURNING
        VALUE(rv_command) TYPE string.
ENDCLASS.



CLASS zcl_sics_apc IMPLEMENTATION.


  METHOD build_frame.
    CLEAR rs_frame.
    rs_frame-frame_type = cl_apc_tcp_client_manager=>co_frame_type_terminator.
    rs_frame-terminator = cl_abap_char_utilities=>cr_lf.
  ENDMETHOD.


  METHOD clear_messages.
    CLEAR mt_messages.
  ENDMETHOD.


  METHOD connect.
    mo_client->connect( i_timeout = mv_connect_timeout ).
  ENDMETHOD.


  METHOD constructor.
    mv_host = iv_host.
    mv_port = iv_port.
    mv_ssl_id = iv_ssl_id.
    mv_connect_timeout = iv_connect_timeout.
    mv_protocol = COND i(
      WHEN iv_use_tls = abap_true
        THEN cl_apc_tcp_client_manager=>co_protocol_type_tcps
      ELSE cl_apc_tcp_client_manager=>co_protocol_type_tcp ).

    create_client( ).
  ENDMETHOD.


  METHOD create_client.
    mo_client = cl_apc_tcp_client_manager=>create(
      i_protocol      = mv_protocol
      i_host          = mv_host
      i_port          = mv_port
      i_frame         = build_frame( )
      i_event_handler = me
      i_ssl_id        = mv_ssl_id ).

    mo_message_manager ?= mo_client->get_message_manager( ).
  ENDMETHOD.


  METHOD disconnect.
    IF mo_client IS BOUND.
      mo_client->close( i_reason = iv_reason ).
    ENDIF.
  ENDMETHOD.


  METHOD execute.
    clear_messages( ).
    send_command( iv_command ).
    rv_response = receive( iv_timeout_seconds ).
  ENDMETHOD.


  METHOD get_connection_id.
    rv_connection_id = mo_client->get_context( )->get_connection_id( ).
  ENDMETHOD.


  METHOD get_last_error.
    rv_last_error = mv_last_error.
  ENDMETHOD.


  METHOD if_apc_wsp_event_handler~on_close.
    mv_is_open = abap_false.
    mv_is_closed = abap_true.
    mv_close_reason = i_reason.
    mv_close_code = i_code.
    mv_last_error = i_reason.
  ENDMETHOD.


  METHOD if_apc_wsp_event_handler~on_error.
    mv_is_open = abap_false.
    mv_is_closed = abap_true.
    mv_close_reason = i_reason.
    mv_close_code = i_code.
    mv_last_error = i_reason.
  ENDMETHOD.


  METHOD if_apc_wsp_event_handler~on_message.
    DATA lv_message TYPE string.

    CASE i_message->get_message_type( ).
      WHEN if_apc_wsp_message=>co_message_type_text.
        lv_message = i_message->get_text( ).
      WHEN if_apc_wsp_message=>co_message_type_binary.
        lv_message = cl_abap_codepage=>convert_from( i_message->get_binary( ) ).
      WHEN OTHERS.
        CLEAR lv_message.
    ENDCASE.

    IF lv_message IS NOT INITIAL.
      APPEND lv_message TO mt_messages.
    ENDIF.
  ENDMETHOD.


  METHOD if_apc_wsp_event_handler~on_open.
    mv_is_open = abap_true.
    mv_is_closed = abap_false.
    CLEAR mv_last_error.
    CLEAR mv_close_reason.
    CLEAR mv_close_code.
  ENDMETHOD.


  METHOD is_connected.
    rv_connected = xsdbool(
      mo_client->get_context( )->get_connection_state( ) = if_apc_wsp_client=>co_connection_state_open ).
  ENDMETHOD.


  METHOD normalize_command.
    rv_command = iv_command.

    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN rv_command WITH ``.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN rv_command WITH ``.
  ENDMETHOD.


  METHOD receive.
    DATA lv_index TYPE i.
    DATA lv_loops TYPE i.

    lv_loops = CONV i( iv_timeout_seconds * 10 ).
    IF lv_loops < 1.
      lv_loops = 1.
    ENDIF.

    DO lv_loops TIMES.
      IF mt_messages IS NOT INITIAL.
        READ TABLE mt_messages INTO rv_response INDEX 1.
        lv_index = sy-tabix.
        DELETE mt_messages INDEX lv_index.
        RETURN.
      ENDIF.

      IF mv_is_closed = abap_true.
        RETURN.
      ENDIF.

      WAIT UP TO '0.1' SECONDS.
    ENDDO.
  ENDMETHOD.


  METHOD send_command.
    DATA(lo_message) = mo_message_manager->create_message( ).

    lo_message->set_text( normalize_command( iv_command ) ).
    mo_message_manager->send( lo_message ).
  ENDMETHOD.
ENDCLASS.
