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

