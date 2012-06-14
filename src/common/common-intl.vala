/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// TODO: This fakes internationalization support until fully integrated.
public unowned string _(string text) {
    return text;
}

public unowned string C_(string context, string text) {
    return text;
}

public unowned string ngettext (string msgid, string msgid_plural, ulong n) {
    return n > 1 ? msgid_plural : msgid;
}

public const string TRANSLATABLE = "TRANSLATABLE";

namespace Intl {
}

