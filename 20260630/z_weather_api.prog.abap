REPORT z_weather_api.

TYPES: BEGIN OF ty_timezone,
         id      TYPE string,
         version TYPE string,
       END OF ty_timezone.

TYPES: BEGIN OF ty_description,
         text          TYPE string,
         language_code TYPE string,
       END OF ty_description.

TYPES: BEGIN OF ty_weather_condition,
         icon_base_uri TYPE string,
         description   TYPE ty_description,
         type          TYPE string,
       END OF ty_weather_condition.

TYPES: BEGIN OF ty_temperature,
         unit    TYPE string,
         degrees TYPE decfloat34,
       END OF ty_temperature.

TYPES: BEGIN OF ty_feels_like_temp,
         unit    TYPE string,
         degrees TYPE decfloat34,
       END OF ty_feels_like_temp.

TYPES: BEGIN OF ty_dew_point,
         unit    TYPE string,
         degrees TYPE decfloat34,
       END OF ty_dew_point.

TYPES: BEGIN OF ty_heat_index,
         unit    TYPE string,
         degrees TYPE decfloat34,
       END OF ty_heat_index.

TYPES: BEGIN OF ty_wind_chill,
         unit    TYPE string,
         degrees TYPE decfloat34,
       END OF ty_wind_chill.

TYPES: BEGIN OF ty_probability,
         type    TYPE string,
         percent TYPE int4,
       END OF ty_probability.

TYPES: BEGIN OF ty_qpf,
         unit     TYPE string,
         quantity TYPE decfloat34,
       END OF ty_qpf.

TYPES: BEGIN OF ty_precipitation,
         probability TYPE ty_probability,
         snow_qpf    TYPE ty_qpf,
         qpf         TYPE ty_qpf,
       END OF ty_precipitation.

TYPES: BEGIN OF ty_air_pressure,
         mean_sea_level_millibars TYPE decfloat34,
       END OF ty_air_pressure.

TYPES: BEGIN OF ty_wind_direction,
         cardinal TYPE string,
         degrees  TYPE int4,
       END OF ty_wind_direction.

TYPES: BEGIN OF ty_wind_speed,
         unit  TYPE string,
         value TYPE decfloat34,
       END OF ty_wind_speed.

TYPES: BEGIN OF ty_wind_gust,
         unit  TYPE string,
         value TYPE decfloat34,
       END OF ty_wind_gust.

TYPES: BEGIN OF ty_wind,
         direction TYPE ty_wind_direction,
         speed     TYPE ty_wind_speed,
         gust      TYPE ty_wind_gust,
       END OF ty_wind.

TYPES: BEGIN OF ty_visibility,
         unit     TYPE string,
         distance TYPE decfloat34,
       END OF ty_visibility.

TYPES: BEGIN OF ty_temp_change,
         unit    TYPE string,
         degrees TYPE decfloat34,
       END OF ty_temp_change.

TYPES: BEGIN OF ty_history,
         temperature_change TYPE ty_temp_change,
         max_temperature    TYPE ty_temp_change,
         min_temperature    TYPE ty_temp_change,
         snow_qpf           TYPE ty_qpf,
         qpf                TYPE ty_qpf,
       END OF ty_history.

TYPES: BEGIN OF ty_weather_response,
         time_zone                    TYPE ty_timezone,
         weather_condition            TYPE ty_weather_condition,
         temperature                  TYPE ty_temperature,
         feels_like_temperature       TYPE ty_feels_like_temp,
         dew_point                    TYPE ty_dew_point,
         heat_index                   TYPE ty_heat_index,
         wind_chill                   TYPE ty_wind_chill,
         precipitation                TYPE ty_precipitation,
         air_pressure                 TYPE ty_air_pressure,
         wind                         TYPE ty_wind,
         visibility                   TYPE ty_visibility,
         current_conditions_history   TYPE ty_history,
         current_time                 TYPE string,
         is_daytime                   TYPE abap_bool,
         relative_humidity            TYPE int4,
         uv_index                     TYPE int4,
         thunderstorm_probability     TYPE int4,
         cloud_cover                  TYPE int4,
       END OF ty_weather_response.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE g_title.
  PARAMETERS: p_lat    TYPE string OBLIGATORY,
              p_lon    TYPE string OBLIGATORY,
              p_apikey TYPE string OBLIGATORY LOWER CASE,
              p_ssl    TYPE ssfapplssl DEFAULT 'ANONYM' OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b1.

INITIALIZATION.
  g_title = 'Google Maps Weather API Parameters'.

AT SELECTION-SCREEN OUTPUT.
  LOOP AT screen.
    IF screen-name = 'P_APIKEY'.
      screen-invisible = '1'.
      MODIFY screen.
    ENDIF.
  ENDLOOP.

START-OF-SELECTION.
  DATA: lo_http_client TYPE REF TO if_http_client,
        lv_url         TYPE string.

  " Construct Google Maps Weather API lookup URL
  lv_url = |https://weather.googleapis.com/v1/currentConditions:lookup?key={ cl_http_utility=>escape_url( p_apikey ) }| &
           |&location.latitude={ cl_http_utility=>escape_url( p_lat ) }&location.longitude={ cl_http_utility=>escape_url( p_lon ) }|.

  cl_http_client=>create_by_url(
    EXPORTING
      url                = lv_url
      ssl_id             = p_ssl
    IMPORTING
      client             = lo_http_client
    EXCEPTIONS
      argument_not_found = 1
      plugin_not_active  = 2
      internal_error     = 3
      OTHERS             = 4 ).

  IF sy-subrc <> 0.
    WRITE: / 'Failed to create HTTP client. sy-subrc:', sy-subrc.
    RETURN.
  ENDIF.

  lo_http_client->send(
    EXCEPTIONS
      http_communication_failure = 1
      http_invalid_state         = 2
      http_processing_failed     = 3
      http_invalid_timeout       = 4
      OTHERS                     = 5 ).

  IF sy-subrc = 0.
    lo_http_client->receive(
      EXCEPTIONS
        http_communication_failure = 1
        http_invalid_state         = 2
        http_processing_failed     = 3
        OTHERS                     = 4 ).
  ENDIF.

  IF sy-subrc <> 0.
    DATA: lv_err_code TYPE i,
          lv_err_msg  TYPE string.
    lo_http_client->get_last_error(
      IMPORTING
        code    = lv_err_code
        message = lv_err_msg ).
    WRITE: / 'HTTP request failed:', lv_err_msg, 'Code:', lv_err_code.
    lo_http_client->close( ).
    RETURN.
  ENDIF.

  DATA: lv_http_status TYPE i.
  lo_http_client->response->get_status( IMPORTING code = lv_http_status ).
  IF lv_http_status <> 200.
    DATA(lv_status_text) = lo_http_client->response->get_header_field( '~status_line' ).
    DATA(lv_error_payload) = lo_http_client->response->get_cdata( ).
    WRITE: / 'HTTP Error Status:', lv_http_status, lv_status_text.
    WRITE: / 'Response Payload:', lv_error_payload.
    lo_http_client->close( ).
    RETURN.
  ENDIF.

  DATA(lv_json) = lo_http_client->response->get_cdata( ).
  lo_http_client->close( ).

  IF lv_json IS INITIAL.
    WRITE: / 'Received empty response from weather API.'.
    RETURN.
  ENDIF.

  DATA: ls_response TYPE ty_weather_response.

  /ui2/cl_json=>deserialize(
    EXPORTING
      json         = lv_json
      pretty_name  = /ui2/cl_json=>pretty_mode-camel_case
    CHANGING
      data         = ls_response ).

  " Output formatted weather conditions
  WRITE: / 'Current Weather Conditions'.
  ULINE.
  WRITE: / 'Location Coordinates:', p_lat, ',', p_lon.
  IF ls_response-time_zone-id IS NOT INITIAL.
    WRITE: / 'Time Zone           :', ls_response-time_zone-id.
  ENDIF.
  WRITE: / 'Current Time        :', ls_response-current_time.
  WRITE: / 'Condition           :', ls_response-weather_condition-description-text,
                                '(', ls_response-weather_condition-type, ')'.
  WRITE: / 'Temperature         :', ls_response-temperature-degrees, ls_response-temperature-unit.
  WRITE: / 'Feels Like          :', ls_response-feels_like_temperature-degrees, ls_response-feels_like_temperature-unit.
  WRITE: / 'Dew Point           :', ls_response-dew_point-degrees, ls_response-dew_point-unit.
  WRITE: / 'Relative Humidity   :', ls_response-relative_humidity, '%'.
  WRITE: / 'Wind Speed          :', ls_response-wind-speed-value, ls_response-wind-speed-unit.
  WRITE: / 'Wind Direction      :', ls_response-wind-direction-cardinal, '(', ls_response-wind-direction-degrees, '°)'.
  WRITE: / 'Cloud Cover         :', ls_response-cloud_cover, '%'.
  WRITE: / 'Visibility          :', ls_response-visibility-distance, ls_response-visibility-unit.
  WRITE: / 'Precipitation Prob. :', ls_response-precipitation-probability-percent, '% (', ls_response-precipitation-probability-type, ')'.
  WRITE: / 'UV Index            :', ls_response-uv_index.
