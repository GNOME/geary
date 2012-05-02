set(ICONS_DEST share/geary/icons)

set(ICON_FILES
    application-menu.svg
    archive.svg
    archive-insert.svg
    geary.png
    mail-inbox.png
    mail-sent.png
    multiple-tags.png
    non-starred-grey.png
    one-tag.png
    starred.png
)

install(FILES ${ICON_FILES} DESTINATION ${ICONS_DEST})
install(FILES geary.png DESTINATION share/icons/hicolor/scalable/apps)


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

