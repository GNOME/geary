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
                buf.append("REP");
            }
            if (this.is_any_set(CONVERSATIONS)) {
                if (buf.len > 0) {
                    buf.append_c('|');
                }
                buf.append("CNV");
            }
            if (this.is_any_set(PERIODIC)) {
                if (buf.len > 0) {
                    buf.append_c('|');
                }
                buf.append("PER");
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
                buf.append("NRM");
            }
            if (this.is_any_set(DESERIALIZER)) {
                if (buf.len > 0) {
                    buf.append_c('|');
                }
                buf.append("DES");
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

    private State[] states;
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
        this.states = new State[fields.length];
        int state_count = 0;
        foreach (GLib.LogField field in fields) {
            switch (field.key) {
            case "GEARY_LOGGING_SOURCE":
                this.states[state_count++] =
                    ((Source) field.value).to_logging_state();
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

        this.states.length = state_count;
    }

    /**
     * Sets the well-known logging source properties.
     *
     * Call this before trying to access {@link account}, {@link
     * folder} and {@link service}. Determining these can be
     * computationally complex and hence is not done by default.
     */
    public void fill_well_known_sources() {
        if (!this.filled) {
            foreach (unowned State state in this.states) {
                GLib.Type type = state.source.get_type();
                if (type.is_a(typeof(Account))) {
                    this.account = (Account) state.source;
                } else if (type.is_a(typeof(ClientService))) {
                    this.service = (ClientService) state.source;
                } else if (type.is_a(typeof(Folder))) {
                    this.folder = (Folder) state.source;
                }
            }
            this.filled = true;
        }
    }

    /** Returns a formatted string representation of this record. */
    public string format() {
        fill_well_known_sources();

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

        if (flags != NONE) {
            str.append_printf("[%s]: ", flags.to_string());
        } else {
            str.append(": ");
        }

        // Append in reverse so inner sources appear first
        for (int i = this.states.length - 1; i >= 0; i--) {
            str.append("[");
            str.append(this.states[i].format_message());
            str.append("] ");
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

// The two locks below can't be nullable. See
// https://gitlab.gnome.org/GNOME/vala/issues/812

private GLib.Mutex record_lock;
private Record? first_record = null;
private Record? last_record = null;
private uint log_length = 0;
private uint max_log_length = 0;
private unowned LogRecord? listener = null;

private GLib.Mutex writer_lock;
private unowned FileStream? stream = null;


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
    writer_lock = GLib.Mutex();
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
    // Keep the old first record so we don't cause any records to be
    // finalised while under the lock, leading to deadlock if
    // finalisation causes any more logging to be generated.
    Record? old_first = null;

    // Obtain a lock since other threads could be calling this or
    // generating more logging at the same time.
    record_lock.lock();
    old_first = first_record;
    first_record = null;
    last_record = null;
    log_length = 0;
    record_lock.unlock();

    // Manually clear each log record in a loop so that finalisation
    // of each is an iterative process. If we just nulled out the
    // record, finalising the first would cause second to be
    // finalised, which would finalise the third, etc., and the
    // recursion could cause the stack to blow right out for large log
    // buffers.
    while (old_first != null) {
        old_first = old_first.next;
    }
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
 * Registers a FileStream to receive all log output from the engine.
 *
 * This may be via the specialized Logging calls (which use the
 * topic-based {@link Flag} or GLib's standard issue
 * debug/message/error/etc. calls ... thus, calling this will also
 * affect the Engine user's calls to those functions.
 *
 * If stream is null, no logging occurs (the default). If non-null and
 * the stream was previously null, all pending log records will be
 * output before proceeding.
 */
public void log_to(FileStream? stream) {
    bool catch_up = (stream != null && Logging.stream == null);
    Logging.stream = stream;
    if (catch_up) {
        Record? record = Logging.first_record;
        while (record != null) {
            write_record(record, record.levels);
            record = record.next;
        }
    }
}


public GLib.LogWriterOutput default_log_writer(GLib.LogLevelFlags levels,
                                               GLib.LogField[] fields) {
    Record record = new Record(fields, levels, GLib.get_real_time());

    // Keep the old first record so we don't cause any records to be
    // finalised while under the lock, leading to deadlock if
    // finalisation causes any more logging to be generated.
    Record? old_record = null;

    // Update the record linked list. Obtain a lock since multiple
    // threads could be calling this function at the same time.
    record_lock.lock();
    old_record = first_record;
    if (first_record == null) {
        first_record = record;
        last_record = record;
    } else {
        last_record.next = record;
        last_record = record;
    }
    // Drop the first if we are already at maximum length
    if (log_length == max_log_length) {
        first_record = first_record.next;
    } else {
        log_length++;
    }
    record_lock.unlock();

    // Now that we are out of the lock, it is safe to finalise any old
    // records.
    old_record = null;

    // Ensure the listener is updated on the main loop only, since
    // this could be getting called from other threads.
    if (listener != null) {
        GLib.MainContext.default().invoke(() => {
                listener(record);
                return GLib.Source.REMOVE;
            });
    }

    write_record(record, levels);

    return GLib.LogWriterOutput.HANDLED;
}

private inline void write_record(Record record,
                                 GLib.LogLevelFlags levels) {
    // Print a log message to the stream if configured, or if the
    // priority is high enough.
    unowned FileStream? out = stream;
    if (out != null ||
        LogLevelFlags.LEVEL_WARNING in levels ||
        LogLevelFlags.LEVEL_CRITICAL in levels  ||
        LogLevelFlags.LEVEL_ERROR in levels) {

        if (out == null) {
            out = GLib.stderr;
        }

        // Lock the writer here so two different threads don't
        // interleave their lines.
        writer_lock.lock();
        out.puts(record.format());
        out.putc('\n');
        writer_lock.unlock();
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
