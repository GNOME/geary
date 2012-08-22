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
set(VERSION "0.1.0+trunk")
set(VERSION_INFO "Release")
set(LANGUAGE_SUPPORT_DIRECTORY ${CMAKE_INSTALL_PREFIX}/share/locale)

# Packaging filenamesnames.
set(ARCHIVE_BASE_NAME ${CMAKE_PROJECT_NAME}-${VERSION})
set(ARCHIVE_FULL_NAME ${ARCHIVE_BASE_NAME}.tar.xz)
set(ARCHIVE_DEBUILD_FULL_NAME ${CMAKE_PROJECT_NAME}_${VERSION}.orig.tar.xz)

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
add_subdirectory(theming)
add_subdirectory(ui)
add_subdirectory(help)

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

# Dist
# This generates the dist tarballs
add_custom_target(
    dist
    COMMAND 
        git archive --prefix=${ARCHIVE_BASE_NAME}/ HEAD
        | xz -z > ${CMAKE_BINARY_DIR}/${ARCHIVE_FULL_NAME}
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
)

# Ubuntu
# Builds the source Debian package used for the Launchpad PPA
add_custom_target(
    ubuntu_pre
    DEPENDS
        dist
    COMMAND 
        ${CMAKE_COMMAND} -E copy ${ARCHIVE_FULL_NAME} ${ARCHIVE_DEBUILD_FULL_NAME}
    COMMAND
        tar xvfx ${ARCHIVE_FULL_NAME}
)

add_custom_target(
    ubuntu
    DEPENDS
        ubuntu_pre
    COMMAND
        ${CMAKE_COMMAND} -E copy_directory "${CMAKE_CURRENT_SOURCE_DIR}/debian" 
        "${CMAKE_CURRENT_BINARY_DIR}/${ARCHIVE_BASE_NAME}/debian"
    COMMAND 
        debuild -S -k$ENV{GPGKEY}
    COMMAND

    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${ARCHIVE_BASE_NAME}"
)

