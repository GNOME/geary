
set(TRANSLATED
    ar
    ca
    cs
    da
    de
    el
    en_CA
    en_GB
    eo
    es
    et
    eu
    fa
    fi
    fr
    gl
    he
    hi
    hr
    hu
    id
    it
    ja
    km
    lt
    ms
    nb
    nl
    pl
    pt
    pt_BR
    ro
    ru
    sk
    sl
    sr
    sv
    te
    tr
    uk
    vi
    zh_CN
    zh_TW
)

IF (XGETTEXT_FOUND)
    GETTEXT_CREATE_TRANSLATIONS(${GETTEXT_PACKAGE}.pot ALL ${TRANSLATED}
	    COMMENT "Creating translations.")
ELSE ()
    message(STATUS "xgettext not found")
ENDIF()

