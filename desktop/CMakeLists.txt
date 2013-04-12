#
# Build and install geary.desktop
#

include (FindIntltool)
if (INTLTOOL_MERGE_FOUND)
    INTLTOOL_MERGE_DESKTOP (geary po)
else (INTLTOOL_MERGE_FOUND)
    message (FATAL_ERROR "intltool must be installed to generate .desktop file")
endif (INTLTOOL_MERGE_FOUND)

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
        COMMAND
            update-desktop-database
    )
    
    add_dependencies(post-uninstall uninstall-desktop-update)
else ()
    install(
        CODE "message (STATUS \"Not updating desktop database\")"
    )
endif ()

