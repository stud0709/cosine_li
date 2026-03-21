Generate ABAP report `ztroutl_optimizer` in a local file in ./src 

# Purpose

Remove redundant entries from table `/scwm/troutl`. The table controls routing between intermediate points in a material flow system (LOSC).

# How to check
- If the entry beind inspected is removed from the table, and FM `/scwm/troutl_det` produces exactly the same output for this entity's scenario, this entry is redundant.

# Example
Assume the LOSC table consisting of only these entries (rowId is not part of /scwm/troutl, it's only here to reference rows in this document):

|rowId| LGNUM | VLTYP | VLBER | NLTYP | IPLPA |
|-|-------|-------|-------|-------|-------|
|A|TEST|XX|||ID-Punkt|
|B|TEST||||OUT-1|
|C|TEST|XX|01||ID-Punkt|

 According to the hard-coded sequence in FM `/scwm/troutl_det`, row C will be evaluated first, row A second, row B third. So if we remove row C, the scenario "going from VLTYP XX, VLBER 01 to **any** NLTYP, NLBER, ..." will still return ILPLA = 'ID-PUNKT'. Therefore, row A can be deleted without breaking the existing behavior.

# Report workflow
- upload a similar csv file from the user's machine
- process the data
- download the result in the same format to the user's machine

# Instructions
- Generate local class doing the actual work.
- The table data shall be passed via `CHANGING` parameter.

# Caveats
- pay attention to the hard-coded access sequence and BAdI invocation spots. 
- BAdI implementations are not available on this system, assume that they can handle the new dataset in the appropriate way. 

# File with sample data 
./scwm_troutl.csv

