# FindIntltool.cmake
#
# Jim Nelson <jim@yorba.org>
# Copyright 2016 Software Freedom Conservancy Inc.

find_program (INTLTOOL_MERGE_EXECUTABLE intltool-merge)

if (INTLTOOL_MERGE_EXECUTABLE)
    set (INTLTOOL_MERGE_FOUND TRUE)
else (INTLTOOL_MERGE_EXECUTABLE)
    set (INTLTOOL_MERGE_FOUND FALSE)
endif (INTLTOOL_MERGE_EXECUTABLE)

if (INTLTOOL_MERGE_FOUND)
    macro (INTLTOOL_MERGE_DESKTOP desktop_id po_dir)
        add_custom_target (geary.desktop ALL
            ${INTLTOOL_MERGE_EXECUTABLE} --desktop-style ${CMAKE_SOURCE_DIR}/${po_dir}
                ${CMAKE_CURRENT_SOURCE_DIR}/${desktop_id}.desktop.in ${desktop_id}.desktop
        )
        install (FILES ${CMAKE_CURRENT_BINARY_DIR}/geary.desktop DESTINATION ${CMAKE_INSTALL_PREFIX}/share/applications) 
    endmacro (INTLTOOL_MERGE_DESKTOP desktop_id po_dir)
    macro (INTLTOOL_MERGE_AUTOSTART_DESKTOP desktop_id po_dir)
        add_custom_target (geary-autostart.desktop ALL
            ${INTLTOOL_MERGE_EXECUTABLE} --desktop-style ${CMAKE_SOURCE_DIR}/${po_dir}
                ${CMAKE_CURRENT_SOURCE_DIR}/${desktop_id}.desktop.in ${desktop_id}.desktop
        )
        install (FILES ${CMAKE_CURRENT_BINARY_DIR}/geary-autostart.desktop DESTINATION ${CMAKE_INSTALL_PREFIX}/share/applications)
    endmacro (INTLTOOL_MERGE_AUTOSTART_DESKTOP desktop_id po_dir)
    macro (INTLTOOL_MERGE_CONTRACT desktop_id po_dir)
        add_custom_target (geary-attach.contract ALL
            ${INTLTOOL_MERGE_EXECUTABLE} --desktop-style ${CMAKE_SOURCE_DIR}/${po_dir}
                ${CMAKE_CURRENT_SOURCE_DIR}/${desktop_id}.contract.in ${desktop_id}.contract
        )
        install (FILES ${CMAKE_CURRENT_BINARY_DIR}/geary-attach.contract DESTINATION ${CMAKE_INSTALL_PREFIX}/share/contractor)
    endmacro (INTLTOOL_MERGE_CONTRACT desktop_id po_dir)
endif (INTLTOOL_MERGE_FOUND)

