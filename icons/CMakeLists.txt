set(ICONS_DEST share/icons/hicolor/scalable/actions)

set(ICON_FILES
    mail-archive-symbolic.svg
    close-symbolic.svg
    detach-symbolic.svg
    text-x-generic-symbolic.svg
    edit-symbolic.svg
    format-text-remove-symbolic.svg
    mail-drafts-symbolic.svg
    mail-drafts-symbolic-rtl.svg
    mail-forward-symbolic.svg
    mail-forward-symbolic-rtl.svg
    mail-inbox-symbolic.svg
    mail-outbox-symbolic.svg
    mail-reply-all-symbolic.svg
    mail-reply-all-symbolic-rtl.svg
    mail-reply-sender-symbolic.svg
    mail-reply-sender-symbolic-rtl.svg
    mail-sent-symbolic.svg
    mail-sent-symbolic-rtl.svg
    marker-symbolic.svg
    tag-symbolic.svg
    tag-symbolic-rtl.svg
)

install(FILES ${ICON_FILES} DESTINATION ${ICONS_DEST})

# Application icon goes in theme directory
install(FILES "hicolor/16x16/apps/geary.png" DESTINATION share/icons/hicolor/16x16/apps)
install(FILES "hicolor/24x24/apps/geary.png" DESTINATION share/icons/hicolor/24x24/apps)
install(FILES "hicolor/32x32/apps/geary.png" DESTINATION share/icons/hicolor/32x32/apps)
install(FILES "hicolor/48x48/apps/geary.png" DESTINATION share/icons/hicolor/48x48/apps)
install(FILES "hicolor/256x256/apps/geary.png" DESTINATION share/icons/hicolor/256x256/apps)
install(FILES "hicolor/512x512/apps/geary.png" DESTINATION share/icons/hicolor/512x512/apps)
install(FILES "hicolor/symbolic/apps/geary-symbolic.svg" DESTINATION share/icons/hicolor/symbolic/apps)

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

