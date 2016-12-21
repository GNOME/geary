# Geary build script
# Copyright 2016 Software Freedom Conservancy Inc.
#
# Check http://webdev.elementaryos.org/docs/developer-guide/cmake for documentation

cmake_minimum_required(VERSION 2.8)
cmake_policy(VERSION 2.6)

project(geary C)

list(APPEND
  CMAKE_MODULE_PATH
  ${CMAKE_SOURCE_DIR}/cmake
  ${CMAKE_SOURCE_DIR}/cmake/GCR_CMake/macros
  )

#
# Base bits
#
set(GETTEXT_PACKAGE "geary")
set(RELEASE_NAME "Lightweight email client for GNOME.")
set(VERSION "0.11.2-dev")
set(VERSION_INFO "Release")
set(LANGUAGE_SUPPORT_DIRECTORY ${CMAKE_INSTALL_PREFIX}/share/locale)

#
# Primary library minimum version requirements. See src/CMakeLists.txt
# for others.
#
set(TARGET_GLIB 2.42) # Also passed to valac, so don't include a point rev
set(TARGET_GTK 3.14.0)
set(TARGET_WEBKIT 2.10)

if (NOT ISO_CODE_639_XML)
  find_path(ISOCODES_DIRECTORY NAMES iso_639.xml PATHS ${CMAKE_INSTALL_PREFIX} /usr/share/xml/iso-codes)
  if (ISOCODES_DIRECTORY)
    set(ISO_CODE_639_XML ${ISOCODES_DIRECTORY}/iso_639.xml)
  else ()
    message(WARNING "File iso_639.xml not found. Please specify it manually using cmake -DISO_CODE_639_XML=/path/to/iso_639.xml")
  endif ()
else ()
  if (NOT EXISTS ${ISO_CODE_639_XML})
    message(WARNING "The path to iso_639.xml specified in ISO_CODE_639_XML is not valid.")
  endif ()
endif ()

if (NOT ISO_CODE_3166_XML)
  find_path(ISOCODES_DIRECTORY NAMES iso_3166.xml PATHS ${CMAKE_INSTALL_PREFIX} /usr/share/xml/iso-codes)
  if (ISOCODES_DIRECTORY)
    set(ISO_CODE_3166_XML ${ISOCODES_DIRECTORY}/iso_3166.xml)
  else ()
    message(WARNING "File iso_3166.xml not found. Please specify it manually using cmake -DISO_CODE_3166_XML=/path/to/iso_3166.xml")
  endif ()
else ()
  if (NOT EXISTS ${ISO_CODE_3166_XML})
    message(WARNING "The path to iso_3166.xml specified in ISO_CODE_3166_XML is not valid.")
  endif ()
endif ()

# Packaging filenamesnames.
set(ARCHIVE_BASE_NAME ${CMAKE_PROJECT_NAME}-${VERSION})
set(ARCHIVE_FULL_NAME ${ARCHIVE_BASE_NAME}.tar.xz)
set(ARCHIVE_DEBUILD_FULL_NAME ${CMAKE_PROJECT_NAME}_${VERSION}.orig.tar.xz)

if (NOT CMAKE_BUILD_TYPE)
  #default build is -O2 -g
  set(CMAKE_BUILD_TYPE "RelWithDebInfo")
endif()

option(ICON_UPDATE "Run gtk-update-icon-cache after the install." ON)
option(DESKTOP_UPDATE "Run update-desktop-database after the install." ON)
option(DESKTOP_VALIDATE "Check generated desktop file for errors during build." ON)
option(TRANSLATE_HELP "Generate and install translated help documentation." ON)

IF(CMAKE_BUILD_TYPE MATCHES Debug)
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

pkg_check_modules(ENCHANT QUIET enchant)

pkg_check_modules(SQLITE3 sqlite3 REQUIRED)
if (NOT ${SQLITE3_VERSION} VERSION_LESS 3.12)
  include(CheckSymbolExists)
  check_symbol_exists(SQLITE_DBCONFIG_ENABLE_FTS3_TOKENIZER sqlite3.h HAVE_FTS3_TOKENIZER)
    if (NOT HAVE_FTS3_TOKENIZER)
        message(FATAL_ERROR "SQLite3 is missing FTS3 tokenizer support. Please compile it with -DSQLITE_ENABLE_FTS3."
                            " See https://bugzilla.gnome.org/show_bug.cgi?id=763203 for details.")
    endif()
else()
  # detect that the current sqlite3 library has FTS3 support (at run time)
  include(CMakePushCheckState)
  include(CheckCSourceRuns)
  cmake_push_check_state(RESET)
  set(CMAKE_REQUIRED_LIBRARIES sqlite3)
  check_c_source_runs("
      #include <sqlite3.h>
      #include <stdlib.h>
      int main() {
          sqlite3 *db;
          char tmpfile[] = \"sqliteXXXXXX\";
          mkstemp(tmpfile);
          if (sqlite3_open(tmpfile, &db) == SQLITE_OK) {
              return sqlite3_exec(db, \"CREATE VIRTUAL TABLE mail USING fts3(subject, body);\", 0, 0, 0);
          }
          return -1;
      }
  " HAVE_FTS3)
  cmake_pop_check_state()
  if (NOT HAVE_FTS3)
      if (${SQLITE3_VERSION} VERSION_LESS 3.11)
          message(FATAL_ERROR "SQLite3 is missing FTS3 support. Please compile it with -DSQLITE_ENABLE_FTS3.")
      else()
          message(FATAL_ERROR "SQLite3 is missing FTS3 tokenizer support. Please compile it with -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_TOKENIZER.")
      endif()
  endif()
endif()

find_package(Git QUIET)

# intl
include(Gettext)
if (XGETTEXT_FOUND)
    message(STATUS "xgettext found")
else ()
    message(STATUS "xgettext not found")
endif ()

# GResources
include(GlibCompileResourcesSupport)

#
# Unit tests.
#
# We don't use CMake's enable_testing/add_test built-ins because they
# use ctest. It's not called "test" because that is cmake reserved.
add_custom_target(tests ALL geary-test)
add_dependencies(tests geary-test)

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
if (GIT_FOUND)
    add_custom_target(
        dist
        COMMAND
            ${GIT_EXECUTABLE} archive --prefix=${ARCHIVE_BASE_NAME}/ HEAD
            | xz -z > ${CMAKE_BINARY_DIR}/${ARCHIVE_FULL_NAME}
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    )
endif()

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
add_subdirectory(ui)
add_subdirectory(src)
add_subdirectory(test)
