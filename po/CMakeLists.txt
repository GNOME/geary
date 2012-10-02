
set(TRANSLATED
    ca
    ca_ES
    de
    el_GR
    en_CA
    en_GB
    eo
    es
    es_ES
    fi
    fr
    he
    id
    it
    km_KH
    nb
    nl_NL
    pl
    pt
    pt_BR
    ro_RO
    sl
    sr
    sv
    tr_TR
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

