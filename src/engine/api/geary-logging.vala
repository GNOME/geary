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

public const uint DEFAULT_MAX_LOG_BUFFER_LENGTH = 4096;
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

/**
 * A single message sent to the logging system.
 *
 * A record is created for each log message, 
 */
public class LogRecord {


    private string domain;
    private LogLevelFlags flags;
    private int64 timestamp;
    private double elapsed;
    private string message;

    internal LogRecord? next = null;


    internal LogRecord(string domain,
                       LogLevelFlags flags,
                       int64 timestamp,
                       double elapsed,
                       string message) {
        this.domain = domain;
        this.flags = flags;
        this.timestamp = timestamp;
        this.elapsed = elapsed;
        this.message = message;
    }

    public LogRecord? get_next() {
        return this.next;
    }

    public string format() {
        GLib.DateTime time = new GLib.DateTime.from_unix_utc(
            this.timestamp / 1000 / 1000
        ).to_local();
        return "%s %02d:%02d:%02d %lf %s: %s".printf(
            to_prefix(this.flags),
            time.get_hour(), time.get_minute(), time.get_second(),
            this.elapsed,
            this.domain ?? "default",
            this.message
        );
    }

}

private int init_count = 0;
private Flag logging_flags = Flag.NONE;
private unowned FileStream? stream = null;
private Timer? entry_timer = null;

private LogRecord? first_record = null;
private LogRecord? last_record = null;
private uint log_length = 0;
private uint max_log_length = 0;


/**
 * Must be called before ''any'' call to the Logging namespace.
 *
 * This will be initialized by the Engine when it's opened, but
 * applications may want to set up logging before that, in which case,
 * call this directly.
 */
public void init() {
    if (init_count++ != 0)
        return;
    entry_timer = new Timer();
    max_log_length = DEFAULT_MAX_LOG_BUFFER_LENGTH;
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

[PrintfFormat]
public inline void error(Flag flags, string fmt, ...) {
    if (logging_flags.is_any_set(flags))
        logv(DOMAIN, LogLevelFlags.LEVEL_ERROR, fmt, va_list());
}

[PrintfFormat]
public inline void critical(Flag flags, string fmt, ...) {
    if (logging_flags.is_any_set(flags))
        logv(DOMAIN, LogLevelFlags.LEVEL_CRITICAL, fmt, va_list());
}

[PrintfFormat]
public inline void warning(Flag flags, string fmt, ...) {
    if (logging_flags.is_any_set(flags))
        logv(DOMAIN, LogLevelFlags.LEVEL_WARNING, fmt, va_list());
}

[PrintfFormat]
public inline void message(Flag flags, string fmt, ...) {
    if (logging_flags.is_any_set(flags))
        logv(DOMAIN, LogLevelFlags.LEVEL_MESSAGE, fmt, va_list());
}

[PrintfFormat]
public inline void debug(Flag flags, string fmt, ...) {
    if (logging_flags.is_any_set(flags)) {
        logv(DOMAIN, LogLevelFlags.LEVEL_DEBUG, fmt, va_list());
    }
}

public LogRecord? get_logs() {
    return first_record;
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
    LogRecord record = new LogRecord(
        domain,
        log_levels,
        GLib.get_real_time(),
        entry_timer.elapsed(),
        message
    );
    entry_timer.start();

    // Update the record linked list
    if (first_record == null) {
        first_record = record;
        last_record = record;
    } else {
        last_record.next = record;
        last_record = record;
    }
    log_length++;
    while (log_length > max_log_length) {
        first_record = first_record.next;
        log_length--;
    }
    if (first_record == null) {
        last_record = null;
    }

    // Print to the output stream if needed
    unowned FileStream? out = stream;
    if (out != null ||
        ((LogLevelFlags.LEVEL_WARNING & log_levels) > 0) ||
        ((LogLevelFlags.LEVEL_CRITICAL & log_levels) > 0)  ||
        ((LogLevelFlags.LEVEL_ERROR & log_levels) > 0)) {

        if (out == null) {
            out = GLib.stderr;
        }

        out.puts(record.format());
        out.putc('\n');
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
