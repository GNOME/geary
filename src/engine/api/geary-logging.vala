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


/** The logging domain for the engine. */
public const string DOMAIN = "Geary";

/** Specifies the default number of log records retained. */
public const uint DEFAULT_MAX_LOG_BUFFER_LENGTH = 4096;

/**
 * Denotes a type of log message.
 *
 * Logging for each type of log message may be dynamically enabled or
 * disabled at run time by {@link enable_flags} and {@link
 * disable_flags}.
 */
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
    DESERIALIZER,
    ALL = int.MAX;

    public inline bool is_all_set(Flag flags) {
        return (flags & this) == flags;
    }

    public inline bool is_any_set(Flag flags) {
        return (flags & this) != 0;
    }

    public string to_string() {
        GLib.StringBuilder buf = new GLib.StringBuilder();
        if (this == ALL) {
            buf.append("ALL");
        } else if (this == NONE) {
            buf.append("NONE");
        } else {
            if (this.is_any_set(NETWORK)) {
                buf.append("NET");
            }
            if (this.is_any_set(SERIALIZER)) {
                if (buf.len > 0) {
                    buf.append_c('|');
                }
                buf.append("SER");
            }
            if (this.is_any_set(REPLAY)) {
                if (buf.len > 0) {
                    buf.append_c('|');
                }
                buf.append("REPLAY");
            }
            if (this.is_any_set(SQL)) {
                if (buf.len > 0) {
                    buf.append_c('|');
                }
                buf.append("SQL");
            }
            if (this.is_any_set(FOLDER_NORMALIZATION)) {
                if (buf.len > 0) {
                    buf.append_c('|');
                }
                buf.append("NORM");
            }
            if (this.is_any_set(DESERIALIZER)) {
                if (buf.len > 0) {
                    buf.append_c('|');
                }
                buf.append("DESER");
            }
        }
        return buf.str;
    }

}

/**
 * A record of a single message sent to the logging system.
 *
 * A record is created for each message logged, and stored in a
 * limited-length, singly-linked buffer. Applications can retrieve
 * this by calling {@link get_earliest_record} and then {get_next},
 * and can be notified of new records via {@link set_log_listener}.
 */
public class Record {


    /** The GLib domain of the log message, if any. */
    public string? domain { get; private set; default = null; }

    /** Account from which the record originated, if any. */
    public Account? account { get; private set; default = null; }

    /** Client service from which the record originated, if any. */
    public ClientService? service { get; private set; default = null; }

    /** Folder from which the record originated, if any. */
    public Folder? folder { get; private set; default = null; }

    /** The logged flags, if any. */
    public Flag? flags = null;

    /** The logged message, if any. */
    public string? message = null;

    /** The source filename, if any. */
    public string? source_filename = null;

    /** The source filename, if any. */
    public string? source_line_number = null;

    /** The source function, if any. */
    public string? source_function = null;

    /** The logged level, if any. */
    public GLib.LogLevelFlags levels;

    /** Time at which the log message was generated. */
    public int64 timestamp;

    /** The next log record in the buffer, if any. */
    public Record? next { get; internal set; default = null; }

    private Loggable[] loggables;
    private bool filled = false;
    private bool old_log_api = false;


    internal Record(GLib.LogField[] fields,
                    GLib.LogLevelFlags levels,
                    int64 timestamp) {
        this.levels = levels;
        this.timestamp = timestamp;
        this.old_log_api = (
            fields.length > 0 &&
            fields[0].key == "GLIB_OLD_LOG_API"
        );

        // Since GLib.LogField only retains a weak ref to its value,
        // find and ref any values we wish to keep around.
        this.loggables = new Loggable[fields.length];
        int loggable_count = 0;
        foreach (GLib.LogField field in fields) {
            switch (field.key) {
            case "GEARY_LOGGABLE":
                this.loggables[loggable_count++] = (Loggable) field.value;
                break;

            case "GEARY_FLAGS":
                this.flags = (Flag) field.value;
                break;

            case "GLIB_DOMAIN":
                this.domain = field_to_string(field);
                break;

            case "MESSAGE":
                this.message = field_to_string(field);
                break;

            case "CODE_FILE":
                this.source_filename = field_to_string(field);
                break;

            case "CODE_LINE":
                this.source_line_number = field_to_string(field);
                break;

            case "CODE_FUNC":
                this.source_function = field_to_string(field);
                break;
            }
        }

        this.loggables.length = loggable_count;
    }

    /** Returns the record's loggables that aren't well-known. */
    public Loggable[] get_other_loggables() {
        fill_well_known_loggables();

        Loggable[] copy = new Loggable[this.loggables.length];
        int count = 0;
        foreach (Loggable loggable in this.loggables) {
            if (loggable != this.account &&
                loggable != this.service &&
                loggable != this.folder) {
                copy[count++] = loggable;
            }
        }
        copy.length = count;
        return copy;
    }

    /**
     * Sets the well-known loggable properties.
     *
     * Call this before trying to access {@link account}, {@link
     * folder} and {@link service}. Determining these can be
     * computationally complex and hence is not done by default.
     */
    public void fill_well_known_loggables() {
        if (!this.filled) {
            foreach (Loggable loggable in this.loggables) {
                GLib.Type type = loggable.get_type();
                if (type.is_a(typeof(Account))) {
                    this.account = (Account) loggable;
                } else if (type.is_a(typeof(ClientService))) {
                    this.service = (ClientService) loggable;
                } else if (type.is_a(typeof(Folder))) {
                    this.folder = (Folder) loggable;
                }
            }
            this.filled = true;
        }
    }

    /** Returns a formatted string representation of this record. */
    public string format() {
        fill_well_known_loggables();

        string domain = this.domain ?? "[no domain]";
        Flag flags = this.flags ?? Flag.NONE;
        string message = this.message ?? "[no message]";
        double float_secs = this.timestamp / 1000.0 / 1000.0;
        double floor_secs = GLib.Math.floor(float_secs);
        int ms = (int) GLib.Math.round((float_secs - floor_secs) * 1000.0);
        GLib.DateTime time = new GLib.DateTime.from_unix_utc(
            (int64) float_secs
        ).to_local();
        GLib.StringBuilder str = new GLib.StringBuilder.sized(128);
        str.printf(
            "%s %02d:%02d:%02d.%04d %s",
            to_prefix(levels),
            time.get_hour(),
            time.get_minute(),
            time.get_second(),
            ms,
            domain
        );

        if (flags != NONE && flags != ALL) {
            str.append_printf("[%s]: ", flags.to_string());
        } else {
            str.append(": ");
        }

        // Use a compact format for well known ojects
        if (this.account != null) {
            str.append(this.account.information.id);
            str.append_c('[');
            str.append(this.account.information.service_provider.to_value());
            if (this.service != null) {
                str.append_c(':');
                str.append(this.service.configuration.protocol.to_value());
            }
            str.append_c(']');
            if (this.folder == null) {
                str.append(": ");
            }
        } else if (this.service != null) {
            str.append(this.service.configuration.protocol.to_value());
            str.append(": ");
        }
        if (this.folder != null) {
            str.append(this.folder.path.to_string());
            str.append(": ");
        }

        foreach (Loggable loggable in get_other_loggables()) {
            str.append(loggable.to_string());
            str.append_c(' ');
        }

        str.append(message);


        // XXX Don't append source details for the moment because of
        // https://gitlab.gnome.org/GNOME/vala/issues/815
        bool disabled = true;
        if (!disabled && !this.old_log_api && this.source_filename != null) {
            str.append(" [");
            str.append(GLib.Path.get_basename(this.source_filename));
            if (this.source_line_number != null) {
                str.append_c(':');
                str.append(this.source_line_number);
            }
            if (this.source_function != null) {
                str.append_c(':');
                str.append(this.source_function.to_string());
            }
            str.append("]");
        }

        return str.str;
    }

}

/** Specifies the function signature for {@link set_log_listener}. */
public delegate void LogRecord(Record record);

private int init_count = 0;
private Flag logging_flags = Flag.NONE;
private unowned FileStream? stream = null;

// Can't be nullable. See https://gitlab.gnome.org/GNOME/vala/issues/812
private GLib.Mutex record_lock;
private Record? first_record = null;
private Record? last_record = null;
private uint log_length = 0;
private uint max_log_length = 0;
private unowned LogRecord? listener = null;


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
    record_lock = GLib.Mutex();
    max_log_length = DEFAULT_MAX_LOG_BUFFER_LENGTH;
}

/**
 * Clears all log records.
 *
 * Since log records hold references to Geary engine objects, it may
 * be desirable to clear the records prior to shutdown so that the
 * objects can be destroyed.
 */
public void clear() {
    record_lock.lock();

    first_record = null;
    last_record = null;
    log_length = 0;
    
    record_lock.unlock();
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

/** Sets a function to be called when a new log record is created. */
public void set_log_listener(LogRecord? new_listener) {
    listener = new_listener;
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
    logv(flags, GLib.LogLevelFlags.LEVEL_ERROR, fmt, va_list());
}

[PrintfFormat]
public inline void critical(Flag flags, string fmt, ...) {
    logv(flags, GLib.LogLevelFlags.LEVEL_CRITICAL, fmt, va_list());
}

[PrintfFormat]
public inline void warning(Flag flags, string fmt, ...) {
    logv(flags, GLib.LogLevelFlags.LEVEL_WARNING, fmt, va_list());
}

[PrintfFormat]
public inline void message(Flag flags, string fmt, ...) {
    logv(flags, GLib.LogLevelFlags.LEVEL_MESSAGE, fmt, va_list());
}

[PrintfFormat]
public inline void debug(Flag flags, string fmt, ...) {
    logv(flags, GLib.LogLevelFlags.LEVEL_DEBUG, fmt, va_list());
}

public inline void logv(Flag flags,
                        GLib.LogLevelFlags level,
                        string fmt,
                        va_list args) {
    if (flags == ALL || logging_flags.is_any_set(flags)) {
        GLib.log_structured_array(
            level,
            new GLib.LogField[] {
                GLib.LogField<string>() {
                    key = "GLIB_DOMAIN", value = DOMAIN, length = -1
                },
                GLib.LogField<Flag>() {
                    key = "GEARY_FLAGS", value = flags, length = 0
                },
                GLib.LogField<string>() {
                    key = "MESSAGE", value = fmt.vprintf(args), length = -1
                }
            }
        );
    }
}

/** Returns the oldest log record in the logging system's buffer. */
public Record? get_earliest_record() {
    return first_record;
}

/** Returns the most recent log record in the logging system's buffer. */
public Record? get_latest_record() {
    return last_record;
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


public GLib.LogWriterOutput default_log_writer(GLib.LogLevelFlags levels,
                                               GLib.LogField[] fields) {
    // Obtain a lock since multiple threads can be calling this
    // function at the same time
    record_lock.lock();

    // Update the record linked list
    Record record = new Record(fields, levels, GLib.get_real_time());
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

    if (listener != null) {
        GLib.MainContext.default().invoke(() => {
                listener(record);
                return GLib.Source.REMOVE;
            });
    }

    // Print a log message to the stream
    unowned FileStream? out = stream;
    if (out != null ||
        LogLevelFlags.LEVEL_WARNING in levels ||
        LogLevelFlags.LEVEL_CRITICAL in levels  ||
        LogLevelFlags.LEVEL_ERROR in levels) {

        if (out == null) {
            out = GLib.stderr;
        }

        out.puts(record.format());
        out.putc('\n');
    }

    record_lock.unlock();

    return GLib.LogWriterOutput.HANDLED;
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

private inline string? field_to_string(GLib.LogField field) {
    string? value = null;
    if (field.length < 0) {
        value = (string) field.value;
    } else if (field.length > 0) {
        value = ((string) field.value).substring(0, field.length);
    }
    return value;
}

}
