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
    CONVERSATIONS,
    PERIODIC,
    TRANSACTIONS;
    
    public inline bool is_all_set(Flag flags) {
        return (flags & this) == flags;
    }
    
    public inline bool is_any_set(Flag flags) {
        return (flags & this) != 0;
    }
}

private Flag logging_flags = Flag.NONE;
private unowned FileStream? stream = null;

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

public void log_to(FileStream stream) {
    Logging.stream = stream;
    
    // TODO: Should handle all LogLevels
    Log.set_handler(null, LogLevelFlags.LEVEL_DEBUG, on_log_debug);
}

private void on_log_debug(string? log_domain, LogLevelFlags log_levels, string message) {
    if (stream != null) {
        Time tm = Time.local(time_t());
        stream.printf(" \x001b[%dm[deb]\x001b[0m %02d:%02d:%02d %s\n", 2 + 30 + 60, tm.hour,
            tm.minute, tm.second, message);
    }
}

}   // namespace
