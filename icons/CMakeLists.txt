set(ICONS_DEST share/geary/icons)

set(ICON_FILES
    application-menu.svg
    archive.svg
    archive-insert.svg
    mail-inbox.png
    mail-sent.png
    menu-down.svg
    non-starred-grey.png
    remove-formatting.png
    starred.png
)

set(ICON_FILES_16
    16x16/tag.svg
    16x16/tag-new.svg
)

set(ICON_FILES_24
    24x24/mail-move.svg
    24x24/tag.svg
    24x24/tag-new.svg
)

install(FILES ${ICON_FILES} DESTINATION ${ICONS_DEST})

install(FILES ${ICON_FILES_16} DESTINATION ${ICONS_DEST}/16x16)
install(FILES ${ICON_FILES_24} DESTINATION ${ICONS_DEST}/24x24)

# Application icon goes in theme directory
install(FILES "48x48/geary.svg" DESTINATION share/icons/hicolor/48x48/apps)
install(FILES "128x128/geary.svg" DESTINATION share/icons/hicolor/128x128/apps)

# Optional: update icon cache at install time.
if (ICON_UPDATE)
    install(
        CODE
            "execute_process (COMMAND gtk-update-icon-cache -t -f ${CMAKE_INSTALL_PREFIX}/share/icons/hicolor)"
        CODE
            "message (STATUS \"Updating icon cache\")"
    )
    
    add_custom_target(
        uninstall-icon-cache
        DEPENDS
            uninstall
        COMMAND
            gtk-update-icon-cache -t -f ${CMAKE_INSTALL_PREFIX}/share/icons/hicolor
    )
endif ()

