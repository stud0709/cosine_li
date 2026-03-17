# FM `/SCWM/TROUTL_DET` — Functional Explanation

## What it does in one sentence

Given a warehouse task's source and destination coordinates, HU attributes, and MFS context, this function determines **which layout-oriented routing entry from customizing table `/SCWM/TROUTL`** should govern the task's intermediate destination, process type, and MFS conveyor-control behaviour.

---

## Context: where it fits in the process

This FM is called during **warehouse task creation / determination** (storage-control layout step, transaction LT0A / internal WT creation). Its job is to resolve the *intermediate* leg of a movement — what storage type/section/bin the HU should be routed through, and which process type and conveyor segment govern that routing. It is **not** responsible for the final destination; it resolves the intermediate layout stop.

---

## Inputs (what the caller provides)

| Parameter | Meaning |
|---|---|
| `IV_LGNUM` | Warehouse number |
| `IV_VLTYP` / `IV_VLBER` | Source storage type and section |
| `IV_NLTYP` / `IV_NLBER` / `IV_NLPLA` | Destination storage type, section, bin |
| `IV_HUTYPGRP` | HU type group of the HU being moved |
| `IV_HOMVE` | Home vehicle indicator (whether the HU belongs to a vehicle) |
| `IV_WTCODE` | WT code — distinguishes normal, MFS, MFS-clarification, and MFS-follow-up tasks |
| `IS_HUHDR` | Full HU header (identity, current bin, HU type) |
| `IS_MFS_CONF` | MFS error state from a previous determination pass |
| `IS_ORDIM_O` | Open delivery/order item — passed to capacity checks |
| `IV_CLARIFY_SEG` | Whether a clarification segment is expected |

---

## Step 1 — Static caching of `/SCWM/TROUTL`

**Hard-coded rule:** The entire `/SCWM/TROUTL` table for the warehouse is loaded into a STATICS variable (`st_troutl`) on the **first call per warehouse number** and reused for every subsequent call within the same function group session. If the warehouse number changes, the cache is cleared and reloaded.

If the table has no entries for this warehouse (`sy-subrc <> 0`), the function sets a STATICS empty-flag (`sv_troutl_empty`) and logs message `/SCWM/WM_SEL i037` ("No routing entries found") on every subsequent call without touching the database again.

**Implication for configuration:** If you add new entries to `/SCWM/TROUTL` during a live session, the running ABAP work process will not see them until the session resets. In practice this is irrelevant for production but matters when testing in a shared development system.

---

## Step 2 — MFS error pass-through

**Hard-coded rule:** If `IS_MFS_CONF-error` is set (the HU already has an MFS error from a previous determination cycle), the entire 36-level matching loop is **skipped**. The function proceeds directly to step 4 (the BAdI call), passing whatever destination is currently set. This avoids re-running the full determination when the system already knows the HU is in an error state.

---

## Step 3 — The 36-level specificity cascade (the heart of the FM)

This is where the customizing entry is selected. The function performs a **DO loop** iterating over 36 candidate match levels against the in-memory copy of `/SCWM/TROUTL`. The levels represent every possible combination of the five routing key fields (besides warehouse number), ordered from most-specific to least-specific:

| Key field | Values tested in priority order |
|---|---|
| `VLTYP` (source storage type) | Actual value → blank (wildcard) |
| `VLBER` (source section) | Actual value → blank |
| `NLTYP` (destination storage type) | Actual value → blank |
| `NLBER` (destination section) | Actual value → blank |
| `HUTYPGRP` (HU type group) | Actual value → blank |
| `HOMVE` (home vehicle flag) | Actual value → blank |

The priority table (embedded as a comment in the code) looks like this (x = actual value, blank = wildcard):

```
Level  VLTYP VLBER NLTYP NLBER HUTYPGRP HOMVE
  1      x     x     x     x      x       x    ← most specific
  2      x     x     x     x      x
  3      x     x     x     x              x
  4      x     x     x     x
 ...
 24      x     x
 25            x     x      x      x      x
 ...
 36                                            ← warehouse-level catch-all
```

**Hard-coded rule:** The level sequence is entirely fixed in code — there is no configuration that alters it. Source type+section always outrank destination type+section; HU type group and home-vehicle flag are the last two dimensions to be stripped off. The only way to change this priority order is a code modification.

**Hard-coded rule:** Each `READ TABLE` uses an exact key match (no fuzzy or range matching). The first level that finds a hit wins. The matched entry is removed from the working table (`DELETE lt_troutl INDEX lv_tabix`) so that the same entry cannot match twice.

### MFS capacity and segment check within the loop

If an HU header is provided (`IS_HUHDR IS NOT INITIAL`), each matched entry is immediately validated by FM **`/SCWM/MFS_WT_R2S_CHK`** before being accepted. This FM checks:

- Whether the **target MFS conveyor segment** (`ls_troutl-cseg`) and its **control point (CP)** are active and not in error.
- Whether the segment has **sufficient capacity** for the HU.
- A BAdI for capacity check is invoked inside that FM (not surfaced at this level).

Results:

- Capacity/status OK → entry goes into `lt_troutl_fit` (the "good routes" list).
- Capacity/status failed → entry goes into `lt_troutl_nofit` (the "no-capacity routes" list), with the exception code (`exccode`), error quantifier, and incident-process code (`iprcode`) recorded.
- MFS customizing missing for the segment → `/SCWM/CX_MFS` is caught, `EV_MFS_ERROR = 'X'` is set, and the function returns immediately (no destination assigned).

**Hard-coded rule:** If the BAdI `lv_badi_continue = 'X'` flag is returned from `/SCWM/MFS_WT_R2S_CHK` (the capacity-check BAdI requested a continue), the loop does **not** stop at the matched level but increments `lv_level` by 1 and tries the next level. This allows an implementation to say "try the next-less-specific entry" when capacity fails. However, the `lv_level` counter can never exceed 32 in continue mode — levels 33–36 (those with no VLTYP at all) are not retried via this mechanism.

---

## Step 4 — Route selection from the fit/nofit lists

**If `lt_troutl_fit` is not empty (at least one route passed capacity check):**

1. **BAdI `/SCWM/EX_CORE_LSC_PRIO` → method `sort`** is called (if an instance is bound) to let a customer implementation re-order the fit candidates and nominate the winner (`ES_TROUTL`). This BAdI is filter-based on `LGNUM`.
2. **Hard-coded rule:** This BAdI call is **skipped when `IV_WTCODE = wmegc_wtcode_mfs_cla`** (clarification tasks). For clarification tasks the first entry in `lt_troutl_fit` is always used directly, without custom prioritisation.
3. If the BAdI returns no winner (or is not implemented), the first entry in `lt_troutl_fit` is used.

**If `lt_troutl_fit` is empty but `lt_troutl_nofit` is not empty (all matching routes failed capacity):**

The nofit list is sorted by `errquan` (error quantifier — lower = less severe). Then:

1. **BAdI `/SCWM/EX_CORE_LSC_PRIO` → method `sort_nofit`** is called (if bound) to let a customer implementation choose the preferred no-capacity route (`ES_TROUTL`). Again, **skipped for clarification WT codes**.
2. If the BAdI returns no winner, the first entry (least-severe error) is used.

The no-capacity result then branches on the **incident-process code (`iprcode`)** of the selected entry and the **source bin's MFS role** (`T331` storage-type role):

| Source bin role | `iprcode` | Hard-coded behaviour |
|---|---|---|
| `wmegc_strole_mfs_ctrl` (MFS control point) | any | Do not forward to PLC; create HU-WT with `wtcode=MFS`; log message `/SCWM/MFS i092` |
| non-MFS | `wmegc_iprcode_nsnd` (no-send) | Same: hold WT, `wtcode=MFS`, log i092 |
| non-MFS | `wmegc_iprcode_crcl` (circular / clarify) | Route HU to clarification bin; set `EV_MFS_WTCODE = wmegc_wtcode_mfs_cla`; log i093 |
| non-MFS | `wmegc_iprcode_stay` (stay) | Do not create WT at all; set `EV_MFS_ERROR = 'X'`; log i094 |
| non-MFS | anything else (default) | Same as `nsnd`: hold WT, `wtcode=MFS`, log i092 |

`EV_MFS_NOCAPA = 'X'` is always set when the nofit path is taken, to signal the caller to schedule a background re-determination (`WT_DET_PREP`).

---

## Step 5 — No route found at all

If both `lt_troutl_fit` and `lt_troutl_nofit` are empty, the function checks whether the situation is legitimately MFS-related before raising an error:

- If `IV_NLPLA` (the destination bin) is a **known MFS control point** with PLC mode `wmegc_mfs_plc_mode_pal_rsrc` (pallet resource), AND the bin is **not** flagged as an end-point (`flg_end`) and **not** a NIO/clarification point (`flg_nio`):
  - `EV_MFS_ERROR = 'X'` is set unless the destination CP is a start-point (`flg_start`) and the source bin is **not** a control point — in which case the error is cleared (the HU is in front of the automatic and no route is yet needed).
  - Logs `/SCWM/MFS i003` ("No routing entry found for MFS task").
- If the destination bin is not an MFS control point, the source bin's own MFS status is checked. If the source is an MFS control point (non-end, non-NIO, pallet-resource mode), `EV_MFS_ERROR = 'X'` is set and an MFS alert is sent to the alert monitor via `raise_mfs_alert_wt_inact`.

**Hard-coded rule:** For non-MFS scenarios where no route is found, no error flag is set and no message is logged — the function simply returns blank destinations. It is the caller's responsibility to interpret blank `EV_ILTYP`/`EV_ILBER`/`EV_ILPLA` as "no intermediate routing required."

---

## Step 6 — BAdI `/SCWM/EX_CORE_LSC_LAYOUT` (final override)

After all determination logic is complete, **`/SCWM/BADI_STORAGE_CTRL_LAYOUT`** is called **unconditionally** — regardless of whether a route was found, whether an MFS error was set, or what the WT code is. This is the customer-exit BAdI for the layout determination result.

The wrapper FM (`/SCWM/LBADI_TOU09`) reveals the following:

- BAdI definition: **`/SCWM/EX_CORE_LSC_LAYOUT`**, interface **`/SCWM/IF_EX_CORE_LSC_LAYOUT`**, method **`layout`**.
- The BAdI receives as read-only context: warehouse number, source/destination type+section, homve, HU type group, clarify segment, WT code, full HU header, MFS config, open delivery item.
- It receives as `CHANGING`: `cv_iltyp`, `cv_ilber`, `cv_ilpla`, `cv_iprocty`, `cv_ppoint`, `cv_ipoint`, `cv_mfs_error`, `cv_mfs_cs`, `cv_mfs_wtcode`.
- It also receives `IS_ORIG_VALUES` — a snapshot of what the values were **before** the BAdI call, so the implementation can compare and conditionally apply its own logic.
- The wrapper detects post-call changes and logs accordingly: i047 if destination changed, i048 if destination was cleared.
- **Filter: `lgnum`** — implementations can be made warehouse-specific.

**What the BAdI can do:**

- Override the intermediate destination (change storage type/section/bin).
- Suppress a route by clearing `cv_iltyp`, `cv_ilber`, `cv_ilpla`.
- Change the process type or conveyor segment.
- Override the MFS error flag (e.g. clear it to allow a WT, or set it to suppress one).
- Change the WT code (e.g. switch from normal MFS to clarification).

---

## Step 7 — Clarification exccode propagation

**Hard-coded rule:** If the final `EV_MFS_WTCODE` is `wmegc_wtcode_mfs_cla` (clarification) and the no-capacity selected entry had an `exccode` (exception code), the exception code is written to the HU header field `MFSERROR` via FM **`/SCWM/HUHDR_ATTR_CHANGE`**. This ensures the clarification reason is persisted on the HU for downstream visibility.

---

## Summary of BAdIs

| BAdI | Definition | Filter | Called when | What you can do |
|---|---|---|---|---|
| **`/SCWM/EX_CORE_LSC_PRIO`** | Enhancement spot | `LGNUM` | After routing candidates are found (both fit and nofit lists) | Re-order or select the winning route from the fit list (`sort` method) or the nofit list (`sort_nofit` method). Cannot be used for clarification WT codes. |
| **`/SCWM/EX_CORE_LSC_LAYOUT`** | Enhancement spot | `LGNUM` | Always, at the very end | Override any aspect of the routing result: destination, process type, MFS error flag, WT code. Has access to both the final result and the original pre-BAdI values. |

There is a third BAdI for capacity checking inside `/SCWM/MFS_WT_R2S_CHK`, but it is not surfaced at this level.

---

## Key hard-coded rules summary

1. **The 36-level specificity order is fixed in code.** You cannot reorder the priority of VLTYP vs NLTYP vs HUTYPGRP via configuration.
2. **`/SCWM/TROUTL` is cached per-session per-warehouse.** Additions to the table are not visible until the work process session resets.
3. **The MFS-error pass-through skips all determination.** If the HU already carries an MFS error flag from a prior pass, the 36-level loop is bypassed entirely.
4. **BAdI `sort`/`sort_nofit` is suppressed for clarification WT codes** (`wmegc_wtcode_mfs_cla`). Clarification tasks always pick the first candidate.
5. **No route + non-MFS = silent blank result.** No error, no message. The caller decides.
6. **The layout BAdI always runs last** — it can override or undo everything that preceded it, including MFS error flags.
7. **Exccode is written to the HU** when routing ends in clarification — not configurable, always happens.
8. **`lv_level` cannot retry above 32** in the BAdI-continue mode — levels 33–36 (no VLTYP) are excluded from the retry escalation path.

