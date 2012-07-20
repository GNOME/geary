##
# Copyright 2009-2010 Jakob Westhoff. All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
#    1. Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
# 
#    2. Redistributions in binary form must reproduce the above copyright notice,
#       this list of conditions and the following disclaimer in the documentation
#       and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY JAKOB WESTHOFF ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
# EVENT SHALL JAKOB WESTHOFF OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# 
# The views and conclusions contained in the software and documentation are those
# of the authors and should not be interpreted as representing official policies,
# either expressed or implied, of Jakob Westhoff
##

include(ParseArguments)
find_package(Vala REQUIRED)

##
# Compile vala files to their c equivalents for further processing. 
#
# The "vala_precompile" macro takes care of calling the valac executable on the
# given source to produce c files which can then be processed further using
# default cmake functions.
# 
# The first parameter provided is a variable, which will be filled with a list
# of c files outputted by the vala compiler. This list can than be used in
# conjuction with functions like "add_executable" or others to create the
# neccessary compile rules with CMake.
#
# The second parameter provided is a name for the "prebuild" target for the
# bundle. This target, when built, will generate C source file from the vala
# source code. The binary executable target should be depend on the prebuild
# target (using add_dependencies). See the example below for details.
# 
# The initial variables are followed by a list of .vala files to be compiled.
# Please take care to add every vala file belonging to the currently compiled
# project or library as Vala will otherwise not be able to resolve all
# dependencies. The paths to these .vala files should be relative to
# CMAKE_CURRENT_SOURCE_DIR.
# 
# The following sections may be specified afterwards to provide certain options
# to the vala compiler:
# 
# EXTERNAL_SOURCES
#   Source files for which there is already a prebuild_target. This is needed
#   because the main source files need to know the names of the .vapi, .vapi.stamp,
#   and .c files. We have already created rules to build those files, we just need
#   their names. The paths to these .vala files should be relative to
#   CMAKE_CURRENT_SOURCE_DIR.
#
# PACKAGES
#   A list of vala packages/libraries to be used during the compile cycle. The
#   package names are exactly the same, as they would be passed to the valac
#   "--pkg=" option.
# 
# OPTIONS
#   A list of optional options to be passed to the valac executable. This can be
#   used to pass "--thread" for example to enable multi-threading support.
#
# DIRECTORY
#   The directory to which build files should be written. If not specified,
#   defaults to CMAKE_CURRENT_BINARY_DIRECTORY. If specified, should be relative to
#   CMAKE_CURRENT_SOURCE_DIRECTORY.
#
# GENERATE_VAPI
#   Pass all the needed flags to the compiler to create an internal vapi for
#   the compiled library. The provided name will be used for this and a
#   <provided_name>.vapi file will be created.
#
# There are two ways to build multi-package applications using vala_precompile: with
# and without a static library. Below are two examples. The first does not use a
# static library. The second does.
#
# Example 1 (no static library):
#   vala_precompile(VALA_LIB_C mylib-prebuild
#       mylib/source1.vala
#       mylib/source2.vala
#       mylib/source3.vala
#   PACKAGES
#       gio-1.0
#       posix
#   OPTIONS
#       --thread
#   DIRECTORY
#       build
#   )
#   # No need to call add_library.
#   
#   vala_precompile(VALA_C myproject-prebuild
#       source1.vala
#       source2.vala
#       source3.vala
#   EXTERNAL_SOURCES
#       mylib/source1.vala
#       mylib/source2.vala
#       mylib/source3.vala
#   PACKAGES
#       gtk+-2.0
#       gio-1.0
#       posix
#   OPTIONS
#       --thread
#   DIRECTORY
#       build
#   )
#   # vala_precompile generates the .c files, but those still need to be compiled
#   # into an executable
#   add_executable(myproject ${VALA_C})
#   # Require that the .c files are generated before cmake attempts to compile them.
#   add_dependencies(myproject myproject-prebuild)
#   # Require that the library's .c files are generated before the main program's .c files.
#   add_dependencies(myproject-prebuild mylib-prebuild)
#
#
# Example 2 (using static library):
#   vala_precompile(VALA_LIB_C mylib-prebuild
#       mylib/source1.vala
#       mylib/source2.vala
#       mylib/source3.vala
#   PACKAGES
#       gio-1.0
#       posix
#   OPTIONS
#       --thread
#   DIRECTORY
#       build
#   GENERATE_VAPI
#       mylib-static-library
#   )
#   add_library(mylib-static-library STATIC ${VALA_LIB_C})
#   add_dependencies(mylib-static-library mylib-prebuild)
#   target_link_libraries(mylib-static-library ${DEPS_LIBRARIES} gthread-2.0)
#
#   vala_precompile(VALA_C myproject-prebuild
#       source1.vala
#       source2.vala
#       source3.vala
#   # Note: No EXTERNAL_SOURCES section, because we use the static library instead.
#   PACKAGES
#       gtk+-2.0
#       gio-1.0
#       posix
#   OPTIONS
#       --thread
#       --vapidir=${CMAKE_BINARY_DIR} # Wherever mylib-static-library.vapi was generated
#   DIRECTORY
#       build
#   )
#   # vala_precompile generates the .c files, but those still need to be compiled
#   # into an executable.
#   add_executable(myproject ${VALA_C})
#   # Require that the static library is built before the .c files are generated.
#   add_dependencies(myproject-prebuild engine-static-library)
#   # Require that the .c files are generated before cmake attempts to compile them.
#   add_dependencies(myproject myproject-prebuild)
#   target_link_libraries(myproject ${DEPS_LIBRARIES} gthread-2.0 mylib-static-library)


# Private helper macro. Takes the name of a vala source file relative to CMAKE_CURRENT_SOURCE_DIR,
# and computes the absolute names of the relevant .vala/.gs, .vapi, .vala.stamp, .dep, and .c files.
macro(add_extensions original_source_name source_name vapi_name vapi_stamp_name dep_name c_name build_dir)
    string(REPLACE ${CMAKE_CURRENT_SOURCE_DIR}/ "" replaced_source_name ${original_source_name})
    get_filename_component(original_extension ${original_source_name} EXT)
    get_filename_component(temp_path ${replaced_source_name}.vala PATH)
    get_filename_component(temp_name_we ${replaced_source_name}.vala NAME_WE)
    set(replaced_basename "${temp_path}/${temp_name_we}")
    
    string(REGEX MATCH "^/" ABSOLUTE_PATH_MATCH ${temp_path})
    if(${ABSOLUTE_PATH_MATCH} MATCHES "/")
        set(absolute_source_basename ${replaced_basename})
        set(absolute_generated_basename "${DIRECTORY}${replaced_basename}")
    else()
        set(absolute_source_basename "${CMAKE_CURRENT_SOURCE_DIR}/${replaced_basename}")
        set(absolute_generated_basename "${DIRECTORY}/${replaced_basename}")
    endif()
    
    set(${source_name} "${absolute_source_basename}${original_extension}")
    set(${vapi_name} "${absolute_generated_basename}.vapi")
    set(${vapi_stamp_name} "${absolute_generated_basename}.vapi.stamp")
    set(${dep_name} "${absolute_generated_basename}.dep")
    set(${c_name} "${absolute_generated_basename}.c")

    if(${ABSOLUTE_PATH_MATCH} MATCHES "/")
        get_filename_component(${build_dir} ${${c_name}} PATH)
    else()
        set(${build_dir} ${DIRECTORY})
    endif()
endmacro(add_extensions)

macro(vala_precompile output prebuild_target)
    parse_arguments(ARGS "EXTERNAL_SOURCES;PACKAGES;OPTIONS;DIRECTORY;GENERATE_VAPI" "" ${ARGN})
    
    if(ARGS_DIRECTORY)
        set(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/${ARGS_DIRECTORY})
    else(ARGS_DIRECTORY)
        set(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})
    endif(ARGS_DIRECTORY)
    
    include_directories(${DIRECTORY})
    
    set(vala_pkg_opts "")
    foreach(pkg ${ARGS_PACKAGES})
        list(APPEND vala_pkg_opts "--pkg=${pkg}")
    endforeach(pkg ${ARGS_PACKAGES})
    
    set(SOURCE_NAMES "")
    set(VAPI_NAMES "")
    set(VAPI_STAMP_NAMES "")
    set(DEP_NAMES "")
    set(C_NAMES "")
    foreach(original_source_name ${ARGS_DEFAULT_ARGS})
        add_extensions(${original_source_name} source_name vapi_name vapi_stamp_name dep_name c_name build_dir)
        
        list(APPEND SOURCE_NAMES ${source_name})
        list(APPEND VAPI_NAMES ${vapi_name})
        list(APPEND VAPI_STAMP_NAMES ${vapi_stamp_name})
        list(APPEND DEP_NAMES ${dep_name})
        list(APPEND C_NAMES ${c_name})
    endforeach(original_source_name ${ARGS_DEFAULT_ARGS})
    
    set(${output} ${C_NAMES})
    
    foreach(original_source_name ${ARGS_EXTERNAL_SOURCES})
        add_extensions(${original_source_name} source_name vapi_name vapi_stamp_name dep_name c_name build_dir)
        list(APPEND VAPI_NAMES ${vapi_name})
        list(APPEND VAPI_STAMP_NAMES ${vapi_stamp_name})
        list(APPEND ${output} ${c_name})
    endforeach(original_source_name ${ARGS_EXTERNAL_SOURCES})
    
    set(full_vapi_name "")
    set(full_vapi_stamp_name "")
    if(ARGS_GENERATE_VAPI)
        set(full_vapi_name ${ARGS_GENERATE_VAPI}.vapi)
        set(full_vapi_stamp_name ${full_vapi_name}.stamp)
        add_custom_command(OUTPUT ${full_vapi_name} COMMAND ":")
        add_custom_command(OUTPUT ${full_vapi_stamp_name}
        COMMAND
            valac
        ARGS
            --fast-vapi=${full_vapi_name}
            ${SOURCE_NAMES}
            && touch ${full_vapi_stamp_name}
        DEPENDS
            ${SOURCE_NAMES}
        )
    endif(ARGS_GENERATE_VAPI)
    
    foreach(original_source_name ${ARGS_DEFAULT_ARGS})
        add_extensions(${original_source_name} source_name vapi_name vapi_stamp_name dep_name c_name build_dir)
        
        add_custom_command(OUTPUT ${vapi_name} COMMAND ":")
        add_custom_command(OUTPUT ${c_name} COMMAND ":")
        
        get_filename_component(vapi_path_name ${vapi_name} PATH)
        add_custom_command(OUTPUT ${vapi_stamp_name}
        COMMAND
            mkdir
        ARGS
            -p
            ${vapi_path_name}
        COMMAND
            valac
        ARGS
            --fast-vapi=${vapi_name}
            ${source_name}
            && touch ${vapi_stamp_name}
        DEPENDS
            ${source_name}
        )
        
        set(temp_vapi_names ${VAPI_NAMES})
        list(REMOVE_ITEM temp_vapi_names ${vapi_name})
        
        set(use_fast_vapi_flags "")
        foreach(temp_vapi_name ${temp_vapi_names})
            list(APPEND use_fast_vapi_flags "--use-fast-vapi=${temp_vapi_name}")
        endforeach(temp_vapi_name ${temp_vapi_names})
        
        get_filename_component(dep_path_name ${dep_name} PATH)
        add_custom_command(OUTPUT ${dep_name}
        COMMAND
            mkdir
        ARGS
            -p
            ${dep_path_name}
        COMMAND
            valac
        ARGS
            "-C"
            "-b" ${CMAKE_CURRENT_SOURCE_DIR}
            "-d" ${build_dir} 
            ${vala_pkg_opts}
            ${ARGS_OPTIONS}
            --deps=${dep_name}
            ${use_fast_vapi_flags}
            ${source_name}
        DEPENDS
            ${source_name}
            ${VAPI_NAMES}
            ${full_vapi_name}
        )
    endforeach(original_source_name ${ARGS_DEFAULT_ARGS})
    
    add_custom_target(${prebuild_target} DEPENDS ${VAPI_STAMP_NAMES} ${full_vapi_stamp_name} ${DEP_NAMES})
endmacro(vala_precompile)

