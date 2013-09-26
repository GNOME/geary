set(ICONS_DEST share/geary/icons)

set(ICON_FILES
    archive-symbolic.svg
    close-symbolic.svg
    document-symbolic.svg
    edit-symbolic.svg
    format-text-remove-symbolic.svg
    forward-symbolic.svg
    forward-rtl-symbolic.svg
    inbox-symbolic.svg
    marker-symbolic.svg
    outbox-symbolic.svg
    read-symbolic.svg
    reply-all-symbolic.svg
    reply-all-rtl-symbolic.svg
    reply-symbolic.svg
    reply-rtl-symbolic.svg
    sent-symbolic.svg
    sent-rtl-symbolic.svg
    spam-symbolic.svg
    spam-rtl-symbolic.svg
    star-symbolic.svg
    tag-symbolic.svg
    tag-rtl-symbolic.svg
    unread-symbolic.svg
    unstarred-symbolic.svg
)

install(FILES ${ICON_FILES} DESTINATION ${ICONS_DEST})

# Application icon goes in theme directory
install(FILES "16x16/geary.svg" DESTINATION share/icons/hicolor/16x16/apps)
install(FILES "32x32/geary.svg" DESTINATION share/icons/hicolor/32x32/apps)
install(FILES "48x48/geary.svg" DESTINATION share/icons/hicolor/48x48/apps)
install(FILES "64x64/geary.svg" DESTINATION share/icons/hicolor/64x64/apps)
install(FILES "128x128/geary.svg" DESTINATION share/icons/hicolor/128x128/apps)

# Optional: update icon cache at install time.
if (ICON_UPDATE)
    install(
        CODE
            "execute_process (COMMAND gtk-update-icon-cache -t -f ${CMAKE_INSTALL_PREFIX}/share/icons/hicolor)"
        CODE
            "message (STATUS \"Updated icon cache in ${CMAKE_INSTALL_PREFIX}/share/icons/hicolor\")"
    )
    
    add_custom_target(
        uninstall-icon-cache
        COMMAND
            gtk-update-icon-cache -t -f ${CMAKE_INSTALL_PREFIX}/share/icons/hicolor
        COMMENT
            "Updated icon cache after uninstall in ${CMAKE_INSTALL_PREFIX}/share/icons/hicolor"
    )
    
    add_dependencies(post-uninstall uninstall-icon-cache)
endif ()

