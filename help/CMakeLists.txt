set(HELP_DEST share/gnome/help/geary/C)

set(HELP_FILES
    C/accounts.page
    C/archive.page
    C/bugs.page
    C/index.page
    C/label.page
    C/limits.page
    C/overview.page
    C/preferences.page
    C/search.page
    C/shortcuts.page
    C/star.page
    C/write.page
)

install(FILES ${HELP_FILES} DESTINATION ${HELP_DEST})
install(FILES C/figures/geary.svg DESTINATION ${HELP_DEST}/figures)

