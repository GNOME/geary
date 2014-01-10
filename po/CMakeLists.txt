
file(STRINGS "LINGUAS" TRANSLATED)

IF (XGETTEXT_FOUND)
    GETTEXT_CREATE_TRANSLATIONS(ALL ${TRANSLATED}
	    COMMENT "Creating translations.")
ELSE ()
    message(STATUS "xgettext not found")
ENDIF()

