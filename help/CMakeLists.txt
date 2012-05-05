set(HELP_DEST share/gnome/help/geary/C)

set(HELP_FILES
    C/archive.page
    C/bugs.page
    C/conversation.page
    C/editor.page
    C/index.page
    C/limits.page
    C/send.page
    C/shortcuts.page
    C/spell.page
    C/star.page
)

install(FILES ${HELP_FILES} DESTINATION ${HELP_DEST})
install(FILES C/figures/Mail.png DESTINATION ${HELP_DEST}/figures)

