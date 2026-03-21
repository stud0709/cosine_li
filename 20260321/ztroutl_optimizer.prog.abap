REPORT ztroutl_optimizer.

*----------------------------------------------------------------------*
* Purpose : Identify and remove redundant entries from /SCWM/TROUTL.
*
* An entry is considered redundant when removing it from the table and
* re-running the /SCWM/TROUTL_DET access sequence (levels 1-36, BAdI
* assumed benign / no active lo_lsc_prio sort on this system) still
* returns an identical result for the same call scenario.
*
* Workflow:
*   1. Upload a CSV export of /SCWM/TROUTL (semicolon-separated,
*      header row, same column order as the table).
*   2. The local class LCL_OPTIMIZER analyses the table in memory and
*      marks redundant entries.
*   3. Download the annotated CSV: original rows extended with a
*      REDUNDANT column ('X' = redundant, '' = keep).
*----------------------------------------------------------------------*

CLASS lcl_optimizer DEFINITION DEFERRED.

*----------------------------------------------------------------------*
* Selection screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS: p_file  TYPE string LOWER CASE OBLIGATORY.   " upload path
  PARAMETERS: p_out   TYPE string LOWER CASE OBLIGATORY.   " download path
  PARAMETERS: p_lgnum TYPE /scwm/lgnum OBLIGATORY. " warehouse to analyse
SELECTION-SCREEN END OF BLOCK b1.

*----------------------------------------------------------------------*
* Type declarations
*----------------------------------------------------------------------*
TYPES:
  BEGIN OF ty_troutl_row,
    mandt    TYPE mandt,
    lgnum    TYPE /scwm/lgnum,
    vltyp    TYPE /scwm/ltap_vltyp,
    vlber    TYPE /scwm/de_vlber_lgst,
    nltyp    TYPE /scwm/ltap_nltyp,
    nlber    TYPE /scwm/de_nlber_lgst,
    homve    TYPE /scwm/de_troutl_homve,
    hutypgrp TYPE /scwm/de_hutypgrp,
    seqnr    TYPE /scwm/de_seqnr,
    iltyp    TYPE /scwm/de_iltyp,
    ilber    TYPE /scwm/de_ilber,
    ilpla    TYPE /scwm/de_ilpla,
    procty   TYPE /scwm/de_iprocty,
    ipoint   TYPE /scwm/de_troutl_ip,
    ppoint   TYPE /scwm/de_troutl_pp,
    cseg     TYPE /scwm/de_mfscs,
  END OF ty_troutl_row,

  BEGIN OF ty_output_row,
    mandt    TYPE mandt,
    lgnum    TYPE /scwm/lgnum,
    vltyp    TYPE /scwm/ltap_vltyp,
    vlber    TYPE /scwm/de_vlber_lgst,
    nltyp    TYPE /scwm/ltap_nltyp,
    nlber    TYPE /scwm/de_nlber_lgst,
    homve    TYPE /scwm/de_troutl_homve,
    hutypgrp TYPE /scwm/de_hutypgrp,
    seqnr    TYPE /scwm/de_seqnr,
    iltyp    TYPE /scwm/de_iltyp,
    ilber    TYPE /scwm/de_ilber,
    ilpla    TYPE /scwm/de_ilpla,
    procty   TYPE /scwm/de_iprocty,
    ipoint   TYPE /scwm/de_troutl_ip,
    ppoint   TYPE /scwm/de_troutl_pp,
    cseg     TYPE /scwm/de_mfscs,
    redundant TYPE xfeld,
  END OF ty_output_row,

  " Result of simulated lookup: winning output fields
  BEGIN OF ty_result,
    found    TYPE xfeld,
    iltyp    TYPE /scwm/de_iltyp,
    ilber    TYPE /scwm/de_ilber,
    ilpla    TYPE /scwm/de_ilpla,
    procty   TYPE /scwm/de_iprocty,
    ipoint   TYPE /scwm/de_troutl_ip,
    ppoint   TYPE /scwm/de_troutl_pp,
    cseg     TYPE /scwm/de_mfscs,
  END OF ty_result,

  tt_troutl  TYPE STANDARD TABLE OF ty_troutl_row WITH DEFAULT KEY,
  tt_output  TYPE STANDARD TABLE OF ty_output_row WITH DEFAULT KEY.

*----------------------------------------------------------------------*
* Local class: optimizer
*----------------------------------------------------------------------*
CLASS lcl_optimizer DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS:
      "! Perform the complete redundancy analysis.
      "! @parameter it_troutl  | Table read from CSV (all warehouses)
      "! @parameter iv_lgnum   | Only rows for this LGNUM are analysed
      "! @parameter et_output  | Input rows annotated with REDUNDANT flag
      analyse
        IMPORTING it_troutl TYPE tt_troutl
                  iv_lgnum  TYPE /scwm/lgnum
        EXPORTING et_output TYPE tt_output,

      "! Simulate /SCWM/TROUTL_DET for one call scenario against a
      "! working copy of the table (BAdI benign: take INDEX 1 of fit).
      "! @parameter it_work   | Working table (already sorted by primary key)
      "! @parameter iv_lgnum  | LGNUM
      "! @parameter iv_vltyp  | Source type
      "! @parameter iv_vlber  | Source section
      "! @parameter iv_nltyp  | Destination type
      "! @parameter iv_nlber  | Destination section
      "! @parameter iv_hutypgrp | HU type group
      "! @parameter iv_homve  | HU movement direction
      "! @parameter es_result | Result (found + output fields)
      simulate_lookup
        IMPORTING it_work     TYPE tt_troutl
                  iv_lgnum    TYPE /scwm/lgnum
                  iv_vltyp    TYPE /scwm/ltap_vltyp
                  iv_vlber    TYPE /scwm/de_vlber_lgst
                  iv_nltyp    TYPE /scwm/ltap_nltyp
                  iv_nlber    TYPE /scwm/de_nlber_lgst
                  iv_hutypgrp TYPE /scwm/de_hutypgrp
                  iv_homve    TYPE /scwm/de_troutl_homve
        EXPORTING es_result   TYPE ty_result.

  PRIVATE SECTION.
    CLASS-METHODS:
      "! Return first match for one level of the access sequence.
      try_level
        IMPORTING it_work     TYPE tt_troutl
                  iv_lgnum    TYPE /scwm/lgnum
                  iv_vltyp    TYPE /scwm/ltap_vltyp
                  iv_vlber    TYPE /scwm/de_vlber_lgst  " may be space
                  iv_nltyp    TYPE /scwm/ltap_nltyp     " may be space
                  iv_nlber    TYPE /scwm/de_nlber_lgst  " may be space
                  iv_hutypgrp TYPE /scwm/de_hutypgrp    " may be space
                  iv_homve    TYPE /scwm/de_troutl_homve " may be space
        RETURNING VALUE(rs_row) TYPE ty_troutl_row,

      "! TRUE when two result records have identical output fields.
      results_equal
        IMPORTING is_a TYPE ty_result
                  is_b TYPE ty_result
        RETURNING VALUE(rv_equal) TYPE abap_bool.
ENDCLASS.

CLASS lcl_optimizer IMPLEMENTATION.

  METHOD try_level.
    " Read the first row matching the supplied key combination.
    " The table is sorted by primary key; with HOMVE/HUTYPGRP both in the
    " key, READ TABLE … WITH KEY performs a linear scan, which is correct
    " because the table is not necessarily sorted for a binary search on
    " arbitrary sub-keys.
    READ TABLE it_work INTO rs_row
      WITH KEY lgnum    = iv_lgnum
               vltyp    = iv_vltyp
               vlber    = iv_vlber
               nltyp    = iv_nltyp
               nlber    = iv_nlber
               hutypgrp = iv_hutypgrp
               homve    = iv_homve.
    IF sy-subrc <> 0.
      CLEAR rs_row.
    ENDIF.
  ENDMETHOD.

  METHOD results_equal.
    rv_equal = abap_false.
    IF is_a-found    = is_b-found    AND
       is_a-iltyp    = is_b-iltyp    AND
       is_a-ilber    = is_b-ilber    AND
       is_a-ilpla    = is_b-ilpla    AND
       is_a-procty   = is_b-procty   AND
       is_a-ipoint   = is_b-ipoint   AND
       is_a-ppoint   = is_b-ppoint   AND
       is_a-cseg     = is_b-cseg.
      rv_equal = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD simulate_lookup.
    " Replicate the DO-loop / 36-level access sequence of /SCWM/TROUTL_DET.
    " Assumptions on this system:
    "   - BAdI lo_lsc_prio is NOT actively bound → take INDEX 1 of fit list
    "   - is_huhdr is INITIAL → no /SCWM/MFS_WT_R2S_CHK capacity check
    "   - is_mfs_conf-error is INITIAL → normal path
    " The FM accumulates ALL entries that match the chosen level into
    " lt_troutl_fit; because capa-check is skipped every match is "fit".
    " The winning entry is lt_troutl_fit INDEX 1.

    CLEAR es_result.

    " Blank typed constants for key wildcards
    DATA lv_blank_vltyp    TYPE /scwm/ltap_vltyp.
    DATA lv_blank_vlber    TYPE /scwm/de_vlber_lgst.
    DATA lv_blank_nltyp    TYPE /scwm/ltap_nltyp.
    DATA lv_blank_nlber    TYPE /scwm/de_nlber_lgst.
    DATA lv_blank_hutypgrp TYPE /scwm/de_hutypgrp.
    DATA lv_blank_homve    TYPE /scwm/de_troutl_homve.
    CLEAR: lv_blank_vltyp, lv_blank_vlber, lv_blank_nltyp,
           lv_blank_nlber, lv_blank_hutypgrp, lv_blank_homve.

    DATA ls_hit   TYPE ty_troutl_row.
    DATA lv_level TYPE /scwm/de_seqnr.

    " The FM uses a single DO loop that can revisit levels when a BAdI
    " sets lv_badi_continue, but with a benign BAdI that never happens.
    " We simply iterate levels 1-36 in order; the first hit at any level
    " wins (earliest level = highest specificity).

    DO 36 TIMES.
      lv_level = sy-index.
      CLEAR ls_hit.

      CASE lv_level.
        WHEN 1.   " lgnum vltyp vlber nltyp nlber hutypgrp homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = iv_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = iv_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 2.   " lgnum vltyp vlber nltyp nlber hutypgrp
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = iv_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = iv_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 3.   " lgnum vltyp vlber nltyp nlber homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = iv_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = iv_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 4.   " lgnum vltyp vlber nltyp nlber
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = iv_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = iv_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 5.   " lgnum vltyp vlber nltyp hutypgrp homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = iv_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 6.   " lgnum vltyp vlber nltyp hutypgrp
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = iv_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 7.   " lgnum vltyp vlber nltyp homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = iv_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 8.   " lgnum vltyp vlber nltyp
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = iv_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 9.   " lgnum vltyp nltyp nlber hutypgrp homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = iv_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 10.  " lgnum vltyp nltyp nlber hutypgrp
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = iv_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 11.  " lgnum vltyp nltyp nlber homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = iv_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 12.  " lgnum vltyp nltyp nlber
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = iv_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 13.  " lgnum vltyp nltyp hutypgrp homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 14.  " lgnum vltyp nltyp hutypgrp
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 15.  " lgnum vltyp nltyp homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 16.  " lgnum vltyp nltyp
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 17.  " lgnum vltyp vlber hutypgrp homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = iv_vlber
                      iv_nltyp    = lv_blank_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 18.  " lgnum vltyp vlber hutypgrp
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = iv_vlber
                      iv_nltyp    = lv_blank_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 19.  " lgnum vltyp vlber homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = iv_vlber
                      iv_nltyp    = lv_blank_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 20.  " lgnum vltyp vlber
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = iv_vlber
                      iv_nltyp    = lv_blank_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 21.  " lgnum vltyp hutypgrp homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = lv_blank_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 22.  " lgnum vltyp hutypgrp
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = lv_blank_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 23.  " lgnum vltyp homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = lv_blank_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 24.  " lgnum vltyp
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = iv_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = lv_blank_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 25.  " lgnum nltyp nlber hutypgrp homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = lv_blank_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = iv_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 26.  " lgnum nltyp nlber hutypgrp
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = lv_blank_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = iv_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 27.  " lgnum nltyp nlber homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = lv_blank_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = iv_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 28.  " lgnum nltyp nlber
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = lv_blank_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = iv_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 29.  " lgnum nltyp hutypgrp homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = lv_blank_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 30.  " lgnum nltyp hutypgrp
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = lv_blank_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 31.  " lgnum nltyp homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = lv_blank_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 32.  " lgnum nltyp
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = lv_blank_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = iv_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 33.  " lgnum hutypgrp homve  (no vltyp, no nltyp)
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = lv_blank_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = lv_blank_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 34.  " lgnum hutypgrp
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = lv_blank_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = lv_blank_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = iv_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 35.  " lgnum homve
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = lv_blank_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = lv_blank_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = iv_homve
            RECEIVING rs_row      = ls_hit.
        WHEN 36.  " lgnum only
          CALL METHOD lcl_optimizer=>try_level
            EXPORTING it_work     = it_work
                      iv_lgnum    = iv_lgnum
                      iv_vltyp    = lv_blank_vltyp
                      iv_vlber    = lv_blank_vlber
                      iv_nltyp    = lv_blank_nltyp
                      iv_nlber    = lv_blank_nlber
                      iv_hutypgrp = lv_blank_hutypgrp
                      iv_homve    = lv_blank_homve
            RECEIVING rs_row      = ls_hit.
      ENDCASE.

      IF ls_hit IS NOT INITIAL.
        " Found a matching entry — this is the winner (BAdI benign:
        " we do not accumulate lt_troutl_fit; the first hit per DO
        " iteration is sufficient because the FM deletes the hit row
        " and only continues if BAdI requests it, which it does not).
        es_result-found   = abap_true.
        es_result-iltyp   = ls_hit-iltyp.
        es_result-ilber   = ls_hit-ilber.
        es_result-ilpla   = ls_hit-ilpla.
        es_result-procty  = ls_hit-procty.
        es_result-ipoint  = ls_hit-ipoint.
        es_result-ppoint  = ls_hit-ppoint.
        es_result-cseg    = ls_hit-cseg.
        RETURN.
      ENDIF.
    ENDDO.
  ENDMETHOD.

  METHOD analyse.
    CLEAR et_output.

    " Build the working table for the selected warehouse, sorted by PK.
    DATA lt_all TYPE tt_troutl.
    lt_all = it_troutl.
    SORT lt_all BY lgnum vltyp vlber nltyp nlber hutypgrp homve seqnr.

    " For each row of the target warehouse, determine:
    "   1. The result when row IS in the table (baseline).
    "   2. The result when row is temporarily REMOVED.
    "   → redundant if both results are found=X and outputs identical.

    DATA ls_out  TYPE ty_output_row.
    DATA ls_base TYPE ty_result.
    DATA ls_sans TYPE ty_result.

    LOOP AT lt_all INTO DATA(ls_row) WHERE lgnum = iv_lgnum.
      DATA(lv_tabix) = sy-tabix.

      " Output fields from the entry itself (its own contribution)
      ls_base-found   = abap_true.
      ls_base-iltyp   = ls_row-iltyp.
      ls_base-ilber   = ls_row-ilber.
      ls_base-ilpla   = ls_row-ilpla.
      ls_base-procty  = ls_row-procty.
      ls_base-ipoint  = ls_row-ipoint.
      ls_base-ppoint  = ls_row-ppoint.
      ls_base-cseg    = ls_row-cseg.

      " Simulate lookup without this row to find what would take its place
      DATA lt_sans TYPE tt_troutl.
      lt_sans = lt_all.
      DELETE lt_sans INDEX lv_tabix.

      simulate_lookup(
        EXPORTING it_work     = lt_sans
                  iv_lgnum    = iv_lgnum
                  iv_vltyp    = ls_row-vltyp
                  iv_vlber    = ls_row-vlber
                  iv_nltyp    = ls_row-nltyp
                  iv_nlber    = ls_row-nlber
                  iv_hutypgrp = ls_row-hutypgrp
                  iv_homve    = ls_row-homve
        IMPORTING es_result   = ls_sans ).

      " Copy fields to output
      MOVE-CORRESPONDING ls_row TO ls_out.
      DATA lv_equal TYPE abap_bool.
      CALL METHOD lcl_optimizer=>results_equal
        EXPORTING is_a     = ls_base
                  is_b     = ls_sans
        RECEIVING rv_equal = lv_equal.
      IF lv_equal = abap_true.
        ls_out-redundant = abap_true.
      ELSE.
        ls_out-redundant = abap_false.
      ENDIF.
      APPEND ls_out TO et_output.
    ENDLOOP.

    " Rows for other warehouses pass through without analysis
    LOOP AT it_troutl INTO DATA(ls_other) WHERE lgnum <> iv_lgnum.
      MOVE-CORRESPONDING ls_other TO ls_out.
      CLEAR ls_out-redundant.
      APPEND ls_out TO et_output.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* Helpers: CSV parse / serialise
*----------------------------------------------------------------------*
FORM csv_to_table
  USING    iv_path   TYPE string
  CHANGING ct_rows   TYPE tt_troutl.

  DATA: lt_raw   TYPE TABLE OF string,
        lv_line  TYPE string,
        lt_cells TYPE TABLE OF string,
        lv_cell  TYPE string.

  CLEAR ct_rows.

  cl_gui_frontend_services=>gui_upload(
    EXPORTING
      filename   = iv_path
      filetype   = 'ASC'
    CHANGING
      data_tab   = lt_raw
    EXCEPTIONS
      OTHERS     = 1 ).

  IF sy-subrc <> 0.
    MESSAGE e006(00) WITH iv_path.
    RETURN.
  ENDIF.

  DATA lv_is_header TYPE abap_bool VALUE abap_true.
  LOOP AT lt_raw INTO lv_line.
    IF lv_is_header = abap_true.
      lv_is_header = abap_false.
      CONTINUE.
    ENDIF.
    CLEAR lt_cells.
    SPLIT lv_line AT ';' INTO TABLE lt_cells.

    DATA ls_row TYPE ty_troutl_row.
    CLEAR ls_row.
    READ TABLE lt_cells INDEX  1 INTO lv_cell. ls_row-mandt    = lv_cell.
    READ TABLE lt_cells INDEX  2 INTO lv_cell. ls_row-lgnum    = lv_cell.
    READ TABLE lt_cells INDEX  3 INTO lv_cell. ls_row-vltyp    = lv_cell.
    READ TABLE lt_cells INDEX  4 INTO lv_cell. ls_row-vlber    = lv_cell.
    READ TABLE lt_cells INDEX  5 INTO lv_cell. ls_row-nltyp    = lv_cell.
    READ TABLE lt_cells INDEX  6 INTO lv_cell. ls_row-nlber    = lv_cell.
    READ TABLE lt_cells INDEX  7 INTO lv_cell. ls_row-homve    = lv_cell.
    READ TABLE lt_cells INDEX  8 INTO lv_cell. ls_row-hutypgrp = lv_cell.
    READ TABLE lt_cells INDEX  9 INTO lv_cell. ls_row-seqnr    = lv_cell.
    READ TABLE lt_cells INDEX 10 INTO lv_cell. ls_row-iltyp    = lv_cell.
    READ TABLE lt_cells INDEX 11 INTO lv_cell. ls_row-ilber    = lv_cell.
    READ TABLE lt_cells INDEX 12 INTO lv_cell. ls_row-ilpla    = lv_cell.
    READ TABLE lt_cells INDEX 13 INTO lv_cell. ls_row-procty   = lv_cell.
    READ TABLE lt_cells INDEX 14 INTO lv_cell. ls_row-ipoint   = lv_cell.
    READ TABLE lt_cells INDEX 15 INTO lv_cell. ls_row-ppoint   = lv_cell.
    READ TABLE lt_cells INDEX 16 INTO lv_cell. ls_row-cseg     = lv_cell.

    APPEND ls_row TO ct_rows.
  ENDLOOP.
ENDFORM.


FORM table_to_csv
  USING    iv_path  TYPE string
           it_out   TYPE tt_output.

  DATA: lt_lines TYPE TABLE OF string,
        lv_line  TYPE string.

  " Header
  lv_line = 'MANDT;LGNUM;VLTYP;VLBER;NLTYP;NLBER;HOMVE;HUTYPGRP;SEQNR;'
          & 'ILTYP;ILBER;ILPLA;PROCTY;IPOINT;PPOINT;CSEG;REDUNDANT'.
  APPEND lv_line TO lt_lines.

  LOOP AT it_out INTO DATA(ls_row).
    lv_line = ls_row-mandt    && ';' &&
              ls_row-lgnum    && ';' &&
              ls_row-vltyp    && ';' &&
              ls_row-vlber    && ';' &&
              ls_row-nltyp    && ';' &&
              ls_row-nlber    && ';' &&
              ls_row-homve    && ';' &&
              ls_row-hutypgrp && ';' &&
              ls_row-seqnr    && ';' &&
              ls_row-iltyp    && ';' &&
              ls_row-ilber    && ';' &&
              ls_row-ilpla    && ';' &&
              ls_row-procty   && ';' &&
              ls_row-ipoint   && ';' &&
              ls_row-ppoint   && ';' &&
              ls_row-cseg     && ';' &&
              ls_row-redundant.
    APPEND lv_line TO lt_lines.
  ENDLOOP.

  cl_gui_frontend_services=>gui_download(
    EXPORTING
      filename         = iv_path
      filetype         = 'ASC'
    CHANGING
      data_tab         = lt_lines
    EXCEPTIONS
      OTHERS           = 1 ).

  IF sy-subrc <> 0.
    MESSAGE e006(00) WITH iv_path.
  ENDIF.
ENDFORM.

*----------------------------------------------------------------------*
* START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.

  DATA lt_troutl TYPE tt_troutl.
  DATA lt_output TYPE tt_output.

  " 1. Upload CSV
  PERFORM csv_to_table USING p_file CHANGING lt_troutl.

  IF lt_troutl IS INITIAL.
    MESSAGE 'No data loaded from file' TYPE 'E'.
  ENDIF.

  " 2. Run analysis
  lcl_optimizer=>analyse(
    EXPORTING it_troutl = lt_troutl
              iv_lgnum  = p_lgnum
    IMPORTING et_output = lt_output ).

  " 3. Download result CSV
  PERFORM table_to_csv USING p_out lt_output.

  " 4. Summary message
  DATA lv_total     TYPE i.
  DATA lv_redundant TYPE i.
  DATA ls_cnt       TYPE ty_output_row.
  lv_total     = lines( lt_output ).
  lv_redundant = 0.
  LOOP AT lt_output INTO ls_cnt WHERE redundant = abap_true.
    lv_redundant = lv_redundant + 1.
  ENDLOOP.

  MESSAGE i000(00) WITH lv_total 'rows analysed,' lv_redundant 'redundant.'.
