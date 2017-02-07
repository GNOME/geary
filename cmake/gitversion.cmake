if (VERSION MATCHES "-dev$")
    find_package(Git QUIET)
    if (GIT_FOUND)
        execute_process(COMMAND ${GIT_EXECUTABLE} describe --all --long --dirty
                        WORKING_DIRECTORY ${SRC_DIR}
                        OUTPUT_VARIABLE "GIT_VERSION"
                        OUTPUT_STRIP_TRAILING_WHITESPACE
                        ERROR_QUIET)
        string(REGEX REPLACE "^heads\\/(.*)-0-(g.*)$" "\\1~\\2" GIT_VERSION "${GIT_VERSION}")
        set(VERSION ${GIT_VERSION})
    endif()
endif()

configure_file("${SRC_DIR}/geary-version.vala.in" "${DST_DIR}/geary-version.vala")
