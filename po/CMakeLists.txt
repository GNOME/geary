
file(STRINGS "LINGUAS" TRANSLATED)

IF (XGETTEXT_FOUND)
    GETTEXT_CREATE_POT(geary.pot
        OPTION
        # XXX Keep these in sync with Makevars
        --from-code=UTF-8
        --add-comments
        --keyword=_
        --keyword=N_
        --keyword=C_:1c,2
        --keyword=NC_:1c,2
        --keyword=g_dngettext:2,3
        --keyword=Description
    )
    GETTEXT_CREATE_TRANSLATIONS(ALL ${TRANSLATED}
        COMMENT "Creating translations."
    )
ELSE ()
    message(STATUS "xgettext not found")
ENDIF()
