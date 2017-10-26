#
# Build and install org.gnome.Geary.desktop
#

include (FindDesktopFileValidate)

add_custom_target (org.gnome.Geary.appdata.xml ALL
    ${GETTEXT_MSGFMT_EXECUTABLE} --xml -d '${CMAKE_SOURCE_DIR}/po'
        --template '${CMAKE_CURRENT_SOURCE_DIR}/org.gnome.Geary.appdata.xml.in' -o org.gnome.Geary.appdata.xml
)
add_custom_target (org.gnome.Geary.desktop ALL
    ${GETTEXT_MSGFMT_EXECUTABLE} --desktop -d '${CMAKE_SOURCE_DIR}/po'
        --template '${CMAKE_CURRENT_SOURCE_DIR}/org.gnome.Geary.desktop.in' -o org.gnome.Geary.desktop
)
add_custom_target (geary-autostart.desktop ALL
    ${GETTEXT_MSGFMT_EXECUTABLE} --desktop -d '${CMAKE_SOURCE_DIR}/po'
        --template '${CMAKE_CURRENT_SOURCE_DIR}/geary-autostart.desktop.in' -o geary-autostart.desktop
)

if (DESKTOP_VALIDATE)
    if (DESKTOP_FILE_VALIDATE_FOUND)
        VALIDATE_DESKTOP_FILE (org.gnome.Geary.desktop)
        VALIDATE_DESKTOP_FILE (geary-autostart.desktop)
    else (DESKTOP_FILE_VALIDATE_FOUND)
        message (FATAL_ERROR "desktop-file-validate must be installed to validate generated .desktop file")
    endif (DESKTOP_FILE_VALIDATE_FOUND)
endif (DESKTOP_VALIDATE)

install (FILES ${CMAKE_CURRENT_BINARY_DIR}/org.gnome.Geary.appdata.xml DESTINATION ${CMAKE_INSTALL_PREFIX}/share/metainfo)
install (FILES ${CMAKE_CURRENT_BINARY_DIR}/org.gnome.Geary.desktop DESTINATION ${CMAKE_INSTALL_PREFIX}/share/applications)
install (FILES ${CMAKE_CURRENT_BINARY_DIR}/geary-autostart.desktop DESTINATION ${CMAKE_INSTALL_PREFIX}/share/applications)
install (FILES ${CMAKE_CURRENT_BINARY_DIR}/geary-attach.contract DESTINATION ${CMAKE_INSTALL_PREFIX}/share/contractor)

# Optional: run update-desktop-database at install time.
# (This has to happen after the org.gnome.Geary.desktop file is installed.)
if (DESKTOP_UPDATE)
    install(
        CODE
            "execute_process (COMMAND update-desktop-database)"
        CODE
            "message (STATUS \"Updating desktop database\")"
    )
    
    add_custom_target(
        uninstall-desktop-update
        COMMAND
            update-desktop-database
    )
    
    add_dependencies(post-uninstall uninstall-desktop-update)
else ()
    install(
        CODE "message (STATUS \"Not updating desktop database\")"
    )
endif ()

if (DISABLE_CONTRACT)
    message (STATUS "Install Contractor contract: OFF")
else (DISABLE_CONTRACT)
    message (STATUS "Install Contractor contract: ON")
    if (GETTEXT_FOUND)
        add_custom_target (geary-attach.contract ALL
            ${GETTEXT_MSGFMT_EXECUTABLE} --desktop -d '${CMAKE_SOURCE_DIR}/po'
            --template '${CMAKE_CURRENT_SOURCE_DIR}/geary-attach.contract.desktop.in' -o geary-attach.contract
            DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/geary-attach.contract.desktop.in
        )

# Can't validate Contractor file since it isn't a valid Desktop
# file according to desktop-file-validate from desktop-file-utils 0.22:
# - geary-attach.contract: error: first group is not "Desktop Entry"
# - geary-attach.contract: error: file contains group "Contractor Entry",
#       but groups extending the format should start with "X-"
# - geary-attach.contract: error: filename does not have a .desktop extension
#
#        if (DESKTOP_VALIDATE)
#            if (DESKTOP_FILE_VALIDATE_FOUND)
#                VALIDATE_DESKTOP_FILE (geary-attach.contract)
#            endif (DESKTOP_FILE_VALIDATE_FOUND)
#        endif (DESKTOP_VALIDATE)
    endif (GETTEXT_FOUND)
    install (PROGRAMS geary-attach DESTINATION bin)
endif (DISABLE_CONTRACT)
