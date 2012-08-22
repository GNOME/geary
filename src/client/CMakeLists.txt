#
# Install geary.desktop
#
install(
    FILES
        misc/geary.desktop
    DESTINATION
        share/applications
)

# Optional: run update-desktop-database at install time.
# (This has to happen after the geary.desktop file is installed.)
if (DESKTOP_UPDATE)
    install(
        CODE
            "execute_process (COMMAND update-desktop-database)"
        CODE
            "message (STATUS \"Updating desktop database\")"
    )
    
    add_custom_target(
        uninstall-desktop-update
        DEPENDS
            uninstall
        COMMAND
            update-desktop-database
    )
else ()
    install(
        CODE "message (STATUS \"Not updating desktop database\")"
    )
endif ()

