/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Geary.Logging {

[Flags]
public enum Flag {
    NONE,
    NETWORK,
    SERIALIZER,
    REPLAY,
    CONVERSATIONS;
    
    public inline bool is_all_set(Flag flags) {
        return (flags & this) == flags;
    }
    
    public inline bool is_any_set(Flag flags) {
        return (flags & this) != 0;
    }
}

private Flag logging_flags = Flag.NONE;

/**
 * Replaces the current logging flags with flags.  Use Geary.Logging.Flag.NONE to clear all
 * logging flags.
 */
public void set_flags(Flag flags) {
    logging_flags = flags;
}

/**
 * Adds the supplied flags to the current logging flags without disturbing the others.
 */
public void enable_flags(Flag flags) {
    logging_flags |= flags;
}

/**
 * Removes the supplied flags from the current logging flags without disturbing the others.
 */
public void disable_flags(Flag flags) {
    logging_flags &= ~flags;
}

/**
 * Returns the current logging flags.
 */
public Flag get_flags() {
    return logging_flags;
}

/**
 * Returns true if all the flag(s) are set.
 */
public inline bool are_all_flags_set(Flag flags) {
    return logging_flags.is_all_set(flags);
}

public inline void error(Flag flags, string fmt, ...) {
    if (logging_flags.is_any_set(flags))
        logv(null, LogLevelFlags.LEVEL_ERROR, fmt, va_list());
}

public inline void critical(Flag flags, string fmt, ...) {
    if (logging_flags.is_any_set(flags))
        logv(null, LogLevelFlags.LEVEL_CRITICAL, fmt, va_list());
}

public inline void warning(Flag flags, string fmt, ...) {
    if (logging_flags.is_any_set(flags))
        logv(null, LogLevelFlags.LEVEL_WARNING, fmt, va_list());
}

public inline void message(Flag flags, string fmt, ...) {
    if (logging_flags.is_any_set(flags))
        logv(null, LogLevelFlags.LEVEL_MESSAGE, fmt, va_list());
}

public inline void debug(Flag flags, string fmt, ...) {
    if (logging_flags.is_any_set(flags))
        logv(null, LogLevelFlags.LEVEL_DEBUG, fmt, va_list());
}

}   // namespace
