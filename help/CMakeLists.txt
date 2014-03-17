set(HELP_FILES
    accounts.page
    archive.page
    bugs.page
    index.page
    label.page
    limits.page
    overview.page
    preferences.page
    search.page
    shortcuts.page
    star.page
    write.page
)

# FIXME: don't re-specify this here, instead read it from Makefile.am.
set(TRANSLATED
    el
    es
)

set(HELP_DEST share/gnome/help/geary)

set(HELP_SOURCE)
foreach(_page ${HELP_FILES})
    set(HELP_SOURCE ${HELP_SOURCE} C/${_page})
endforeach()

install(FILES ${HELP_SOURCE} DESTINATION ${HELP_DEST}/C)
install(FILES C/figures/geary.svg DESTINATION ${HELP_DEST}/C/figures)


FIND_PROGRAM(XML2PO_BIN xml2po)
IF(NOT XML2PO_BIN)
    MESSAGE(FATAL_ERROR "xml2po not found")
ENDIF()

# Hacked together from the similar macro in cmake/Gettext.cmake.
MACRO(HELP_CREATE_TRANSLATIONS _firstLang)
    SET(_translatedPages)
    SET(_addToAll)
    SET(_isComment FALSE)

    FOREACH(_lang ${_firstLang} ${ARGN})
        IF(_lang STREQUAL "ALL")
            SET(_addToAll "ALL")
        ELSEIF(_lang STREQUAL "COMMENT")
            SET(_isComment TRUE)
        ELSEIF(_isComment)
            SET(_isComment FALSE)
            SET(_comment ${_lang})
        ELSE()
            GET_FILENAME_COMPONENT(_absPo ${_lang}/${_lang}.po ABSOLUTE)

            FOREACH(_page ${HELP_FILES})
                GET_FILENAME_COMPONENT(_absSourcePage C/${_page} ABSOLUTE)
                SET(_destPage ${CMAKE_CURRENT_BINARY_DIR}/${_lang}/${_page})
                GET_FILENAME_COMPONENT(_destPath ${_destPage} PATH)

                #MESSAGE("_absPo=${_absPo} _absSourcePage=${_absSourcePage} _destPage=${_destPage} _lang=${_lang} _page=${_page} curr_bin=${CMAKE_CURRENT_BINARY_DIR}\n")
                ADD_CUSTOM_COMMAND(
                    OUTPUT ${_destPage}
                    COMMAND mkdir -p ${_destPath} && ${XML2PO_BIN} -m mallard -p ${_absPo} -o ${_destPage} ${_absSourcePage}
                    DEPENDS ${_absPo} ${_absSourcePage}
                    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
                    )

                INSTALL(FILES ${_destPage} DESTINATION ${HELP_DEST}/${_lang})
                SET(_translatedPages ${_translatedPages} ${_destPage})
            ENDFOREACH()
        ENDIF()
    ENDFOREACH()

    IF(DEFINED _comment)
        ADD_CUSTOM_TARGET(help_translations ${_addToAll} DEPENDS ${_translatedPages} COMMENT ${_comment})
    ELSE()
        ADD_CUSTOM_TARGET(help_translations ${_addToAll} DEPENDS ${_translatedPages})
    ENDIF()
ENDMACRO()

HELP_CREATE_TRANSLATIONS(ALL ${TRANSLATED} COMMENT "Translating help docs.")
