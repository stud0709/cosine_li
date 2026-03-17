# /SCWM/TROUTL_DET findings

## Functional purpose

`/SCWM/TROUTL_DET` is the standard EWM function module that determines the storage-control route/layout for a warehouse task.

It evaluates:

- warehouse number
- source storage type and section/group
- destination storage type and section/group
- optional destination bin
- HU type group
- homogeneity indicator
- WT code
- HU / WT context
- MFS context

It returns:

- interim destination type, section, and bin
- process type
- pick point / identification point
- MFS segment
- MFS status and control flags

In practical terms, it decides whether storage control should happen, which route entry from `/SCWM/TROUTL` should be used, and whether MFS rules force a different outcome.

## Main standard logic

### 1. Read `/SCWM/TROUTL`

The FM caches all `/SCWM/TROUTL` entries by warehouse in static memory.

If no entry exists for the warehouse, it logs message `i037(/scwm/wm_sel)` and exits.

### 2. Determine route candidate with a hard-coded fallback matrix

The FM uses a fixed 32-level search sequence over these fields:

- `VLTYP`
- `VLBER`
- `NLTYP`
- `NLBER`
- `HUTYPGRP`
- `HOMVE`

It starts from the most specific combination and progressively replaces fields with blanks.

Examples:

- level 1: all six criteria match
- level 2: same, but `HOMVE` blank
- level 3: same, but `HUTYPGRP` blank
- level 4: both `HUTYPGRP` and `HOMVE` blank

Then it continues by relaxing `NLBER`, `VLBER`, `NLTYP`, and finally even `VLTYP`.

This precedence is hard-coded in ABAP. It is not IMG-configurable.

### 3. Stay on the first matched specificity level

Once entries are found on a given specificity level, standard processing stays on that level.

It does not normally continue to lower-specificity levels. The main exception is an MFS scenario where `/SCWM/MFS_WT_R2S_CHK` returns `EV_CONTINUE_SEARCH = 'X'`.

### 4. Run MFS route readiness / capacity checks

If HU context is present, every candidate route is checked by `/SCWM/MFS_WT_R2S_CHK`.

That check can:

- reject the route because the segment or communication point is inactive
- reject the route because of capacity
- return MFS exception and process codes
- request broader search

Candidates are split into:

- fitting routes
- non-fitting routes

### 5. Prioritize fitting routes

If fitting routes exist and WT code is not the clarification WT code, standard tries BAdI `/SCWM/EX_CORE_LSC_PRIO`.

If no BAdI implementation determines a different winner, standard takes the first fitting route.

### 6. Handle non-fitting routes with hard-coded MFS behavior

If only non-fitting routes exist, standard sorts them by `ERRQUAN`, then may reprioritize them through the same prioritization BAdI.

After that, hard-coded logic applies based on storage type role and `IPRCODE`:

- source storage type role = MFS control
  - do not forward WT to PLC
  - keep/create MFS WT
  - log message `i092(/scwm/mfs)`
- `IPRCODE = NSND`
  - do not send to PLC
  - treat as MFS WT
  - log `i092`
- `IPRCODE = CRCL`
  - move to clarification point
  - set WT code to MFS clarification
  - log `i093`
- `IPRCODE = STAY`
  - do not create follow-up WT
  - leave the main WT inactive
  - set MFS error
  - log `i094`
- any other or missing `IPRCODE`
  - default branch behaves like “do not send to PLC”
  - log `i092`

### 7. If no route is found, still run hard-coded MFS fallback checks

Even without any `/SCWM/TROUTL` match, the FM checks whether the destination or current HU position is in an MFS-relevant communication point.

Important hard-coded outcomes:

- if destination is an MFS pallet-resource PLC point and not endpoint and not NIO:
  - set MFS error
  - leave WT inactive
- special exception:
  - if destination communication point is a start point and the source bin is not a communication point, the error is cleared
- if destination is not MFS but the current HU position is still in an MFS communication point that is not endpoint/NIO:
  - set MFS error
  - log `i003(/scwm/mfs)`
  - raise an MFS alert

### 8. Call customer enhancement at the end

After standard determination, the FM always calls `/SCWM/BADI_STORAGE_CTRL_LAYOUT`.

This gives customer enhancement logic a final chance to change:

- interim destination
- process type
- pick / identification points
- MFS error
- MFS segment
- WT code

If clarification WT is chosen and an exception code exists, the FM writes that exception code back to the HU header with `/SCWM/HUHDR_ATTR_CHANGE`.

## Hard-coded rules to highlight

These points are standard-code behavior, not pure customizing behavior:

- the 32-step match precedence is fixed in ABAP
- once a specificity level matches, lower levels are normally not considered
- lower-level continuation depends on the MFS check returning continue-search
- if several fitting routes exist, first route wins unless prioritization BAdI changes it
- `IPRCODE` handling is hard-coded
- the special treatment of start/end/NIO communication points is hard-coded
- clarification handling writes the exception code back to the HU header

## Available BAdIs / enhancement options

### `/SCWM/EX_CORE_LSC_PRIO`

Purpose:

- prioritize candidate routes

Used for:

- `SORT` of fitting routes
- `SORT_NOFIT` of non-fitting routes

Practical meaning:

- standard determines which `/SCWM/TROUTL` entries are eligible
- this BAdI decides which eligible candidate should win

Limitation:

- it does not replace the hard-coded 32-level search matrix

### `/SCWM/EX_CORE_LSC_LAYOUT`

Called via wrapper FM `/SCWM/BADI_STORAGE_CTRL_LAYOUT`.

Purpose:

- final override or change of storage-control determination after standard logic

The wrapper passes:

- all determination inputs
- the original standard result as `IS_ORIG_VALUES`
- changing parameters for final route and MFS status

This is the most powerful enhancement point for business behavior.

The standard code comment explicitly documents two patterns:

- to create TO to clarification point:
  - clear MFS error
  - set interim destination fields
- to leave HU where it is:
  - set MFS error
  - clear interim destination fields

The wrapper also logs:

- `i047(/scwm/l3)` when storage control was changed
- `i048(/scwm/l3)` when storage control was deactivated

### Possible indirect enhancement inside `/SCWM/MFS_WT_R2S_CHK`

The `/SCWM/TROUTL_DET` source contains a comment stating that the route readiness check includes a BAdI for capacity check.

This note was confirmed from the calling FM source, but the exact BAdI name was not fetched in this pass.

## Consultant-oriented troubleshooting order

If the business question is “why was this route chosen or not chosen?”, the recommended order is:

1. check `/SCWM/TROUTL` entries at the most specific match level
2. check whether MFS readiness/capacity logic rejected them
3. check whether `/SCWM/EX_CORE_LSC_PRIO` reprioritized the candidate list
4. check whether `/SCWM/EX_CORE_LSC_LAYOUT` overrode the final result
5. review communication-point and `IPRCODE` behavior for MFS scenarios

## What is customizable vs not

### Customizable

- contents of `/SCWM/TROUTL`
- route criteria and target values
- MFS customizing that affects readiness / PLC / communication-point behavior
- customer behavior implemented in the BAdIs above

### Not IMG-configurable

- the 32-step matching sequence
- the rule to stay on the first matching specificity level
- the hard-coded `IPRCODE` branches
- the hard-coded start/end/NIO communication-point treatment
- the HU update behavior for clarification cases

