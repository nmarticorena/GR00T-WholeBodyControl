if(NOT DEFINED EXECUTABLE_PATH OR NOT DEFINED RPATH_PREFIX OR
   NOT DEFINED PATCHELF_EXECUTABLE)
  message(FATAL_ERROR "PrependRpath.cmake is missing a required argument")
endif()

execute_process(
  COMMAND "${PATCHELF_EXECUTABLE}" --print-rpath "${EXECUTABLE_PATH}"
  RESULT_VARIABLE print_result
  OUTPUT_VARIABLE current_rpath
  OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT print_result EQUAL 0)
  message(FATAL_ERROR "Could not read RPATH from ${EXECUTABLE_PATH}")
endif()

# Remove an existing occurrence so the prefix appears exactly once and first.
string(REPLACE ":" ";" rpath_entries "${current_rpath}")
list(REMOVE_ITEM rpath_entries "${RPATH_PREFIX}")
list(PREPEND rpath_entries "${RPATH_PREFIX}")
list(JOIN rpath_entries ":" corrected_rpath)

execute_process(
  # DT_RPATH is intentional here: a Pixi activation can place its incompatible
  # libddsc in LD_LIBRARY_PATH, which takes precedence over DT_RUNPATH.
  COMMAND "${PATCHELF_EXECUTABLE}" --force-rpath
          --set-rpath "${corrected_rpath}" "${EXECUTABLE_PATH}"
  RESULT_VARIABLE patch_result)
if(NOT patch_result EQUAL 0)
  message(FATAL_ERROR "Could not update RPATH for ${EXECUTABLE_PATH}")
endif()
