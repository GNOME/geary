
# Search for the valadocc executable in the usual system paths.
find_program(VALADOC_EXECUTABLE NAMES valadoc)

# Handle the QUIETLY and REQUIRED arguments, which may be given to the find call.
# Furthermore set VALA_FOUND to TRUE if Vala has been found (aka.
# VALA_EXECUTABLE is set)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(Valadoc DEFAULT_MSG VALADOC_EXECUTABLE)

mark_as_advanced(VALADOC_EXECUTABLE)

# Determine the valac version
if(VALA_FOUND)
    execute_process(COMMAND ${VALA_EXECUTABLE} "--version" 
                    OUTPUT_VARIABLE "VALA_VERSION")
    string(REPLACE "Vala" "" "VALA_VERSION" ${VALA_VERSION})
    string(STRIP ${VALA_VERSION} "VALA_VERSION")
endif(VALA_FOUND)
