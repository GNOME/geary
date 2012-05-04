set(HELP_DEST share/gnome/help/geary/C)

set(HELP_FILES
    archive.page
    bugs.page
    conversation.page
    editor.page
    index.page
    limits.page
    send.page
    shortcuts.page
    spell.page
    star.page
    figures/Mail.png
   
    
)

install(FILES ${HELP_FILES} DESTINATION ${HELP_DEST})

