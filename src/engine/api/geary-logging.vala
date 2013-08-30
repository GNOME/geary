/* Copyright 2011-2013 Yorba Foundation
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

[Flags]
public enum Flag {
    NONE,
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
    
    log_to(null);
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
    
    Log.set_handler(null, LogLevelFlags.LEVEL_DEBUG,
        (domain, levels, msg) => { on_log(" [deb]", levels, msg); });
    Log.set_handler(null, LogLevelFlags.LEVEL_INFO,
        (domain, levels, msg) => { on_log(" [inf]", levels, msg); });
    Log.set_handler(null, LogLevelFlags.LEVEL_MESSAGE,
        (domain, levels, msg) => { on_log(" [msg]", levels, msg); });
    Log.set_handler(null, LogLevelFlags.LEVEL_WARNING,
        (domain, levels, msg) => { on_log("*[wrn]", levels, msg); });
    Log.set_handler(null, LogLevelFlags.LEVEL_CRITICAL,
        (domain, levels, msg) => { on_log("![crt]", levels, msg); });
    Log.set_handler(null, LogLevelFlags.LEVEL_ERROR,
        (domain, levels, msg) => { on_log("![err]", levels, msg); });
}

private void on_log(string prefix, LogLevelFlags log_levels, string message) {
    if (stream == null)
        return;
    
    Time tm = Time.local(time_t());
    stream.printf("%s %02d:%02d:%02d %lf %s\n", prefix, tm.hour, tm.minute, tm.second,
        entry_timer.elapsed(), message);
    
    entry_timer.start();
}

}

