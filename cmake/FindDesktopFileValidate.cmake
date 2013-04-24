# FindDesktopFileValidate.cmake
#
# Charles Lindsay <chaz@yorba.org>
# Copyright 2013 Yorba Foundation

find_program (DESKTOP_FILE_VALIDATE_EXECUTABLE desktop-file-validate)

if (DESKTOP_FILE_VALIDATE_EXECUTABLE)
    set (DESKTOP_FILE_VALIDATE_FOUND TRUE)
else (DESKTOP_FILE_VALIDATE_EXECUTABLE)
    set (DESKTOP_FILE_VALIDATE_FOUND FALSE)
endif (DESKTOP_FILE_VALIDATE_EXECUTABLE)

if (DESKTOP_FILE_VALIDATE_FOUND)
    macro (VALIDATE_DESKTOP_FILE desktop_id)
        add_custom_command (TARGET ${desktop_id}.desktop POST_BUILD
            COMMAND ${DESKTOP_FILE_VALIDATE_EXECUTABLE} ${desktop_id}.desktop
        )
    endmacro (VALIDATE_DESKTOP_FILE desktop_id)
endif (DESKTOP_FILE_VALIDATE_FOUND)
