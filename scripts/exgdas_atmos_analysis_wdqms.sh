#!/bin/bash
set -x

# Input GSI diagnostic file containing inputs to wdqms.py
CNVSTAT="${CDUMP}.t${cyc}z.cnvstat"

# Input files from CNVSTAT fed to wdqms.py
INPUT_LIST=("diag_conv_ps_ges.${PDY}${cyc}.nc4" \
            "diag_conv_t_ges.${PDY}${cyc}.nc4" \
            "diag_conv_q_ges.${PDY}${cyc}.nc4" \
            "diag_conv_uv_ges.${PDY}${cyc}.nc4")

# Observation types being processed by wdqms.py
OTYPES=(SYNOP TEMP MARINE)

################################################################################
echo "Begin job ${job:-}"

#-------------------------------------------------------------------------------
# Enter working directory
cd "${DATA}" || ( echo "FATAL ERROR: Unable to cd into '${DATA}', ABORT!"; exit 2 )

#-------------------------------------------------------------------------------
# Copy cnvstat file from COMIN to DATA, untar and gunzip input files for wdqms.py
# These should always be available
cp "${COMIN}/${CNVSTAT}" .
rc=$?
(( rc != 0 )) && ( echo "FATAL ERROR: Unable to copy '${CNVSTAT}' from '${COMIN}', ABORT!"; exit 2 )
for diagfile in "${INPUT_LIST[@]}"; do
  tar -xvf "${CNVSTAT}" "${diagfile}.gz"
  rc=$?
  (( rc != 0 )) && ( echo "FATAL ERROR: Unable to extract '${diagfile}.gz' from '${CNVSTAT}', ABORT!"; exit 3 )
  gunzip "${diagfile}.gz"
  rc=$?
  (( rc != 0 )) && ( echo "FATAL ERROR: Unable to gunzip '${diagfile}.gz', ABORT!"; exit 3 )
done

#-------------------------------------------------------------------------------
# Loop over observation types, produce CSV files
# Copy CSV files to COMOUT
# Issue DBN alerts
# Issue warnings if wdqms.py fails for any reason
# These do not need to be a FATAL ERROR, but developers should be notified
error=0
for otype in "${OTYPES[@]}"; do

  echo "Processing ... ${otype}"

  #=============================================================================
  # Process with wdqms.py
  ${WDQMSPY} -i ${INPUT_LIST[@]} -t "${otype}" -o "${DATA}"
  rc=$?
  if (( rc != 0 )); then
    echo "WARNING: wdqms.py failed to process observation type '${otype}'"
    error=$((error + 1))
  fi
  #=============================================================================

  #=============================================================================
  # Copy to COMOUT if wdqms.py created the output file
  csvfile="NCEP_${otype}_${PDY}_${cyc}.csv"
  if [[ -f "${csvfile}" ]]; then
    cp "./${csvfile}" "${COMOUT}/${csvfile}" || ( echo "WARNING: Unable to copy '${csvfile}' to '${COMOUT}'" )
  else
    echo "WARNING: wdqms.py failed to create csvfile '${csvfile}'"
    error=$((error + 1))
  fi
  #=============================================================================

  #=============================================================================
  # Send DBN alerts
  if [[ -f "${COMOUT}/${csvfile}" ]]; then
    if [[ "${SENDDBN:-}" == "YES" ]]; then
      "${DBNROOT}/bin/dbn_alert" MODEL SUB_TYPE "${job}" "${COMOUT}/${csvfile}"  # TODO: NCO SPA will coordinate w/ Dataflow to identify the appropriate SUB_TYPE
    fi
  else
    echo "WARNING: wdqms.py did not produce '${csvfile}'"
    if [[ "${SENDDBN:-}" == "YES" ]]; then
      echo "WARNING: No DBN alert.  File missing: '${COMOUT}/${csvfile}'"
    fi
    error=$((error + 1))
  fi
  #=============================================================================

done  # for otype
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
if (( error == 0 )); then
  echo "Job completed normally."
else
  echo "WARNING: Job completed with non-fatal errors."
fi
################################################################################

exit 0
