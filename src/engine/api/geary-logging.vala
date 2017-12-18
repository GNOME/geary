/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Provides some control over Engine logging.
 *
 * This is a crude implementation and could be improved.  Most importantly, when the Engine is
 * initialized logging is disabled for all users of GLib's logging functions.
 */

namespace Geary.Logging {

private const string DOMAIN = "Geary";

[Flags]
public enum Flag {
    NONE = 0,
    NETWORK,
    SERIALIZER,
    REPLAY,
    CONVERSATIONS,
    PERIODIC,
    SQL,
    FOLDER_NORMALIZATION,
    DESERIALIZER;

    public inline bool is_all_set(Flag flags) {
        return (flags & this) == flags;
    }

    public inline bool is_any_set(Flag flags) {
        return (flags & this) != 0;
    }
}

private int init_count = 0;
private Flag logging_flags = Flag.NONE;
private unowned FileStream? stream = null;
private Timer? entry_timer = null;

/**
 * Must be called before ''any'' call to the Logging namespace.
 *
 * This will be initialized by the Engine when it's opened, but applications may want to set up
 * logging before that, in which case, call this directly.
 */
public void init() {
    if (init_count++ != 0)
        return;
    entry_timer = new Timer();
}

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
        logv(DOMAIN, LogLevelFlags.LEVEL_ERROR, fmt, va_list());
}

public inline void critical(Flag flags, string fmt, ...) {
    if (logging_flags.is_any_set(flags))
        logv(DOMAIN, LogLevelFlags.LEVEL_CRITICAL, fmt, va_list());
}

public inline void warning(Flag flags, string fmt, ...) {
    if (logging_flags.is_any_set(flags))
        logv(DOMAIN, LogLevelFlags.LEVEL_WARNING, fmt, va_list());
}

public inline void message(Flag flags, string fmt, ...) {
    if (logging_flags.is_any_set(flags))
        logv(DOMAIN, LogLevelFlags.LEVEL_MESSAGE, fmt, va_list());
}

public inline void debug(Flag flags, string fmt, ...) {
    if (logging_flags.is_any_set(flags)) {
        logv(DOMAIN, LogLevelFlags.LEVEL_DEBUG, fmt, va_list());
    }
}

/**
 * Registers a FileStream to receive all log output from the Engine, be it via the specialized
 * Logging calls (which use the topic-based {@link Flag} or GLib's standard issue
 * debug/message/error/etc. calls ... thus, calling this will also affect the Engine user's calls
 * to those functions.
 *
 * If stream is null, no logging occurs.  This is default.
 */
public void log_to(FileStream? stream) {
    Logging.stream = stream;
}

public void default_handler(string? domain,
                            LogLevelFlags log_levels,
                            string message) {
    unowned FileStream? out = stream;
    if (out != null ||
        ((LogLevelFlags.LEVEL_WARNING & log_levels) > 0) ||
        ((LogLevelFlags.LEVEL_CRITICAL & log_levels) > 0)  ||
        ((LogLevelFlags.LEVEL_ERROR & log_levels) > 0)) {

        if (out == null) {
            out = GLib.stderr;
        }

        GLib.Time tm = GLib.Time.local(time_t());
        out.printf(
            "%s %02d:%02d:%02d %lf %s: %s\n",
            to_prefix(log_levels),
            tm.hour, tm.minute, tm.second,
            entry_timer.elapsed(),
            domain ?? "default",
            message
        );

        entry_timer.start();
    }
}

private inline string to_prefix(LogLevelFlags level) {
    switch (level) {
    case LogLevelFlags.LEVEL_ERROR:
        return "![err]";

    case LogLevelFlags.LEVEL_CRITICAL:
        return "![crt]";

    case LogLevelFlags.LEVEL_WARNING:
        return "*[wrn]";

    case LogLevelFlags.LEVEL_MESSAGE:
        return " [msg]";

    case LogLevelFlags.LEVEL_INFO:
        return " [inf]";

    case LogLevelFlags.LEVEL_DEBUG:
        return " [deb]";

    case LogLevelFlags.LEVEL_MASK:
        return "![***]";

    default:
        return "![???]";

    }
}

}
