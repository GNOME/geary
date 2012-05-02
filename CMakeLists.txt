# Geary build script
# Copyright 2011-2012 Yorba Foundation
#
# Check http://webdev.elementaryos.org/docs/developer-guide/cmake for documentation

cmake_minimum_required(VERSION 2.8)
cmake_policy(VERSION 2.6)

project(geary C)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake )

#
# Base bits
#
set(GETTEXT_PACKAGE "geary")
set(RELEASE_NAME "Lightweight email client for GNOME.")
set(VERSION "0.0.0+trunk")
set(VERSION_INFO "Release")

option(ICON_UPDATE "Run gtk-update-icon-cache after the install." ON)
option(DESKTOP_UPDATE "Run update-desktop-database after the install." ON)

if (ICON_UPDATE)
    message(STATUS "Icon cache will be updated")
endif ()

if (DESKTOP_UPDATE)
    message(STATUS "Desktop database will be updated")
endif ()


add_subdirectory(src)
add_subdirectory(icons)
add_subdirectory(sql)
add_subdirectory(ui)
add_subdirectory(help)

#
# Install geary.desktop
#
install(
    FILES
        geary.desktop
    DESTINATION
        share/applications
)

#
# Uninstall target
#
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake_uninstall.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake"
    IMMEDIATE @ONLY
)

add_custom_target(
    uninstall
    COMMAND 
        ${CMAKE_COMMAND} -P ${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake
    COMMAND 
        ${glib_schema_compiler} ${GSETTINGS_DIR}
)

# Optional: run update-desktop-database at install time.
if (DESKTOP_UPDATE)
    install(
        CODE
            "execute_process (COMMAND update-desktop-database)"
        CODE
            "message (STATUS \"Updating desktop database\")"
    )
    
    add_custom_target(
        uninstall-desktop-update
        DEPENDS
            uninstall
        COMMAND
            update-desktop-database
    )
endif ()

# Dist
# This generates the dist tarballs
set(ARCHIVE_NAME ${CMAKE_PROJECT_NAME}-${VERSION})
add_custom_target(dist
    COMMAND git archive --prefix=${ARCHIVE_NAME}/ HEAD
        | bzip2 > ${CMAKE_BINARY_DIR}/${ARCHIVE_NAME}.tar.bz2
    COMMAND git archive --prefix=${ARCHIVE_NAME}/ HEAD
        | gzip > ${CMAKE_BINARY_DIR}/${ARCHIVE_NAME}.tar.gz
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})

