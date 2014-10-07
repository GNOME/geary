# Geary build script
# Copyright 2011-2014 Yorba Foundation
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
set(VERSION "0.8.1")
set(VERSION_INFO "Release")
set(LANGUAGE_SUPPORT_DIRECTORY ${CMAKE_INSTALL_PREFIX}/share/locale)

# Packaging filenamesnames.
set(ARCHIVE_BASE_NAME ${CMAKE_PROJECT_NAME}-${VERSION})
set(ARCHIVE_FULL_NAME ${ARCHIVE_BASE_NAME}.tar.xz)
set(ARCHIVE_DEBUILD_FULL_NAME ${CMAKE_PROJECT_NAME}_${VERSION}.orig.tar.xz)

option(DEBUG "Build for debugging." OFF)
option(ICON_UPDATE "Run gtk-update-icon-cache after the install." ON)
option(DESKTOP_UPDATE "Run update-desktop-database after the install." ON)
option(DESKTOP_VALIDATE "Check generated desktop file for errors during build." ON)
option(TRANSLATE_HELP "Generate and install translated help documentation." ON)

if (DEBUG)
    message(STATUS "Debug build")
endif ()

if (ICON_UPDATE)
    message(STATUS "Icon cache will be updated")
endif ()

if (DESKTOP_UPDATE)
    message(STATUS "Desktop database will be updated")
endif ()

if (DESKTOP_VALIDATE)
    message(STATUS "Generated desktop file will be checked for errors")
endif ()

if (TRANSLATE_HELP)
    message(STATUS "Help translations will be generated and installed")
endif ()

find_package(PkgConfig)
pkg_check_modules(LIBUNITY QUIET unity>=5.12.0)
pkg_check_modules(LIBMESSAGINGMENU QUIET messaging-menu>=12.10.2)

# CMake's range-checking syntax doesn't allow for a bare less-than, so using
# improbably high version numbers to indicate maximum
pkg_check_modules(WEBKITGTK24X QUIET webkitgtk-3.0>=2.3.0)
pkg_check_modules(WEBKITGTK22X QUIET webkitgtk-3.0>=2.2.0 webkitgtk-3.0<=2.2.100)
pkg_check_modules(WEBKITGTK20X QUIET webkitgtk-3.0>=2.0.0 webkitgtk-3.0<=2.0.100)
pkg_check_modules(WEBKITGTK110X QUIET webkitgtk-3.0>=1.10.0 webkitgtk-3.0<=1.10.2)

pkg_check_modules(GTK312X QUIET gtk+-3.0>=3.12.0)

# intl
include(Gettext)
if (XGETTEXT_FOUND)
    message(STATUS "xgettext found")
else ()
    message(STATUS "xgettext not found")
endif ()

#
# Uninstall target
#
configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake_uninstall.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake"
    IMMEDIATE @ONLY
)

add_custom_target(
    uninstall-base
    COMMAND 
        ${CMAKE_COMMAND} -P ${CMAKE_CURRENT_BINARY_DIR}/cmake_uninstall.cmake
    COMMAND 
        ${glib_schema_compiler} ${GSETTINGS_DIR}
)

add_custom_target(
    uninstall
)

# We add this dependency using add_dependencies (which makes it run first) rather than
# a depends clause in add_custom_target (which would make it run last).
add_dependencies(uninstall uninstall-base)

# This gets fired in the root-level Makefile to ensure an post-uninstall cleanup happens after
# everything has has been removed
add_custom_target(
    post-uninstall
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

add_subdirectory(desktop)
add_subdirectory(help)
add_subdirectory(icons)
add_subdirectory(po)
add_subdirectory(sql)
add_subdirectory(src)
add_subdirectory(theming)
add_subdirectory(ui)

