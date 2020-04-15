/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2018-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


namespace Geary.Logging {


    /** The logging domain for the engine. */
    public const string DOMAIN = "Geary";

    /** Specifies the default number of log records retained. */
    public const uint DEFAULT_MAX_LOG_BUFFER_LENGTH = 4096;


    /** Specifies the function signature for {@link set_log_listener}. */
    public delegate void LogRecord(Record record);


    private bool was_init = false;

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

    private Gee.Set<string> suppressed_domains;


    /**
     * Must be called before ''any'' call to the Logging namespace.
     *
     * This will be initialized by the Engine when it's opened, but
     * applications may want to set up logging before that, in which case,
     * call this directly.
     */
    public void init() {
        if (!Logging.was_init) {
            Logging.was_init = true;
            Logging.suppressed_domains = new Gee.HashSet<string>();
            Logging.record_lock = GLib.Mutex();
            Logging.writer_lock = GLib.Mutex();
            Logging.max_log_length = DEFAULT_MAX_LOG_BUFFER_LENGTH;
        }
    }

    /**
     * Suppresses debug logging for a given logging domain.
     *
     * If a logging domain is suppressed, DEBUG-level logging will not
     * be sent to the logging system.
     *
     * @see unsuppress_domain
     */
    public void suppress_domain(string domain) {
        Logging.suppressed_domains.add(domain);
    }

    /**
     * Un-suppresses debug logging for a given logging domain.
     *
     * @see suppress_domain
     */
    public void unsuppress_domain(string domain) {
        Logging.suppressed_domains.remove(domain);
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
        Logging.record_lock.lock();
        old_first = first_record;
        Logging.first_record = null;
        Logging.last_record = null;
        Logging.log_length = 0;
        Logging.record_lock.unlock();

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

    /** Sets a function to be called when a new log record is created. */
    public void set_log_listener(LogRecord? new_listener) {
        Logging.listener = new_listener;
    }

    /** Returns the oldest log record in the logging system's buffer. */
    public Record? get_earliest_record() {
        return Logging.first_record;
    }

    /** Returns the most recent log record in the logging system's buffer. */
    public Record? get_latest_record() {
        return Logging.last_record;
    }

    /**
     * Registers a destination for log output from {@link default_log_writer}.
     *
     * If stream is null, no logging occurs (the default). If non-null
     * and the stream was previously null, all pending log records
     * will be output before proceeding.
     *
     * This only has effect if {@link default_log_writer} has been set
     * as the GLib structured log writer via a call to {@link
     * GLib.Log.set_writer_func}.
     */
    public void log_to(GLib.FileStream? stream) {
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


    /**
     * A log writer function for printing GLib structured logging.
     *
     * This only has effect if set as the GLib structured log writer
     * via a call to {@link GLib.Log.set_writer_func} and a non-null
     * stream has been passed to {@link log_to}.
     */
    public GLib.LogWriterOutput default_log_writer(GLib.LogLevelFlags levels,
                                                   GLib.LogField[] fields) {
        Record record = new Record(fields, levels, GLib.get_real_time());
        if (!should_blacklist(record)) {
            // Keep the old first record so we don't cause any records
            // to be finalised while under the lock, leading to
            // deadlock if finalisation causes any more logging to be
            // generated.
            Record? old_record = null;

            // Update the record linked list. Obtain a lock since multiple
            // threads could be calling this function at the same time.
            Logging.record_lock.lock();
            old_record = first_record;
            if (Logging.first_record == null) {
                Logging.first_record = record;
                Logging.last_record = record;
            } else {
                Logging.last_record.next = record;
                Logging.last_record = record;
            }
            // Drop the first if we are already at maximum length
            if (Logging.log_length == Logging.max_log_length) {
                Logging.first_record = Logging.first_record.next;
            } else {
                Logging.log_length++;
            }
            Logging.record_lock.unlock();

            // Now that we are out of the lock, it is safe to finalise any old
            // records.
            old_record = null;

            // Ensure the listener is updated on the main loop only, since
            // this could be getting called from other threads.
            if (Logging.listener != null) {
                GLib.MainContext.default().invoke(() => {
                        Logging.listener(record);
                        return GLib.Source.REMOVE;
                    });
            }

            write_record(record, levels);
        }

        return HANDLED;
    }

    private bool should_blacklist(Record record) {
        const string DOMAIN_PREFIX = Logging.DOMAIN + ".";
        return (
            // Don't need to check for the engine's domains, they were
            // already handled by Source's methods.
            (record.domain != Logging.DOMAIN &&
             !record.domain.has_prefix(DOMAIN_PREFIX) &&
             record.domain in Logging.suppressed_domains) ||
            // GAction does not support disabling parameterised actions
            // with specific values, but GTK complains if the parameter is
            // set to null to achieve the same effect, and they aren't
            // interested in supporting that: GNOME/gtk!1151
            (record.levels == GLib.LogLevelFlags.LEVEL_WARNING &&
             record.domain == "Gtk" &&
             record.message.has_prefix("actionhelper:") &&
             record.message.has_suffix("target type NULL)"))
        );
    }

    private inline void write_record(Record record,
                                     GLib.LogLevelFlags levels) {
        // Print a log message to the stream if configured, or if the
        // priority is high enough.
        unowned FileStream? out = Logging.stream;
        if (out != null ||
            GLib.LogLevelFlags.LEVEL_WARNING in levels ||
            GLib.LogLevelFlags.LEVEL_CRITICAL in levels  ||
            GLib.LogLevelFlags.LEVEL_ERROR in levels) {

            if (out == null) {
                out = GLib.stderr;
            }

            // Lock the writer here so two different threads don't
            // interleave their lines.
            Logging.writer_lock.lock();
            out.puts(record.format());
            out.putc('\n');
            Logging.writer_lock.unlock();
        }
    }


    private inline string to_prefix(GLib.LogLevelFlags level) {
        switch (level) {
        case LEVEL_ERROR:
            return "![err]";

        case LEVEL_CRITICAL:
            return "![crt]";

        case LEVEL_WARNING:
            return "*[wrn]";

        case LEVEL_MESSAGE:
            return " [msg]";

        case LEVEL_INFO:
            return " [inf]";

        case LEVEL_DEBUG:
            return " [deb]";

        case LEVEL_MASK:
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

/**
 * Mixin interface for objects that support structured logging.
 *
 * Logging sources provide both a standard means to obtain a string
 * representation of the object for display to humans, and keep a weak
 * reference to some parent source, enabling context to be
 * automatically added to logging calls. For example, if a Foo object
 * is the logging source parent of a Bar object, log calls made by Bar
 * will automatically be decorated with Foo.
 */
public interface Geary.Logging.Source : GLib.Object {


    /**
     * Returns a string representation of a source based on its state.
     *
     * The string returned will include the source's type name, the
     * its current logging state, and the value of extra_values, if
     * any.
     */
    protected static string default_to_string(Source source,
                                              string extra_values) {
        return "%s(%s%s)".printf(
            source.get_type().name(),
            source.to_logging_state().format_message(),
            extra_values
        );
    }

    // Based on function from with the same name from GLib's
    // gmessages.c. Return value must be 1 byte long (plus nul byte).
    // Reference:
    // http://man7.org/linux/man-pages/man3/syslog.3.html#DESCRIPTION
    private static string log_level_to_priority(GLib.LogLevelFlags level) {
        if (GLib.LogLevelFlags.LEVEL_ERROR in level) {
            return "3";
        }
        if (GLib.LogLevelFlags.LEVEL_CRITICAL in level) {
            return "4";
        }
        if (GLib.LogLevelFlags.LEVEL_WARNING in level) {
            return "4";
        }
        if (GLib.LogLevelFlags.LEVEL_MESSAGE in level) {
            return "5";
        }
        if (GLib.LogLevelFlags.LEVEL_INFO in level) {
            return "6";
        }
        if (GLib.LogLevelFlags.LEVEL_DEBUG in level) {
            return "7";
        }

        /* Default to LOG_NOTICE for custom log levels. */
        return "5";
    }


    protected struct Context {

        // 8 fields ought to be enough for anybody...
        private const uint8 FIELD_COUNT = 8;

        public GLib.LogField[] fields;
        public uint8 len;
        public uint8 count;

        public string message;


        Context(string domain,
                GLib.LogLevelFlags level,
                string message,
                va_list args) {
            this.fields = new GLib.LogField[FIELD_COUNT];
            this.len = FIELD_COUNT;
            this.count = 0;
            append("PRIORITY", log_level_to_priority(level));
            append("GLIB_DOMAIN", domain);

            this.message = message.vprintf(va_list.copy(args));
        }

        public void append<T>(string key, T value) {
            uint8 count = this.count;
            if (count + 1 >= this.len) {
                this.fields.resize(this.len + FIELD_COUNT);
            }

            this.fields[count].key = key;
            this.fields[count].value = value;
            this.fields[count].length = (typeof(T) == typeof(string)) ? -1 : 0;

            this.count++;
        }

        public inline void append_source(Source value) {
            this.append("GEARY_LOGGING_SOURCE", value);
        }

        public GLib.LogField[] to_array() {
            // MESSAGE must always be last, so append it here
            append("MESSAGE", this.message);
            return this.fields[0:this.count];
        }

    }


    /**
     * A value to use as the GLib logging domain for the source.
     *
     * This defaults to {@link DOMAIN}.
     */
    public virtual string logging_domain {
        get { return DOMAIN; }
    }

    /**
     * The parent of this source.
     *
     * If not null, the parent and its ancestors recursively will be
     * added to to log message context.
     */
    public abstract Source? logging_parent { get; }

    /**
     * Returns a loggable representation of this source's current state.
     *
     * Since this source's internal state may change between being
     * logged and being used from a log record, this records relevant
     * state at the time when it was logged so it may be displayed or
     * recorded as it is right now.
     */
    public abstract State to_logging_state();

    /**
     * Returns a string representation of this source based on its state.
     *
     * This simply calls {@link default_to_string} with this source
     * and the empty string, returning the result. Implementations of
     * this interface can call that method if they need to override
     * the default behaviour of this method.
     */
    public virtual string to_string() {
        return Source.default_to_string(this, "");
    }

    /**
     * Logs a debug-level log message with this object as context.
     */
    [PrintfFormat]
    public inline void debug(string fmt, ...) {
        if (!(this.logging_domain in Logging.suppressed_domains)) {
            log_structured(LEVEL_DEBUG, fmt, va_list());
        }
    }

    /**
     * Logs a message-level log message with this object as context.
     */
    [PrintfFormat]
    public inline void message(string fmt, ...) {
        log_structured(LEVEL_MESSAGE, fmt, va_list());
    }

    /**
     * Logs a warning-level log message with this object as context.
     */
    [PrintfFormat]
    public inline void warning(string fmt, ...) {
        log_structured(LEVEL_WARNING, fmt, va_list());
    }

    /**
     * Logs a error-level log message with this object as context.
     */
    [PrintfFormat]
    [NoReturn]
    public inline void error(string fmt, ...) {
        log_structured(LEVEL_ERROR, fmt, va_list());
    }

    /**
     * Logs a critical-level log message with this object as context.
     */
    [PrintfFormat]
    public inline void critical(string fmt, ...) {
        log_structured(LEVEL_CRITICAL, fmt, va_list());
    }

    private inline void log_structured(GLib.LogLevelFlags levels,
                                       string fmt,
                                       va_list args) {
        Context context = Context(this.logging_domain, levels, fmt, args);

        // Don't attempt to this object if it is in the middle of
        // being destructed, which can happen when logging from
        // the destructor.
        Source? decorated = (this.ref_count > 0) ? this : this.logging_parent;
        while (decorated != null) {
            context.append_source(decorated);
            decorated = decorated.logging_parent;
        }

        GLib.log_structured_array(levels, context.to_array());
    }

}

/**
 * A record of the state of a logging source to be recorded.
 *
 * @see Source.to_logging_state
 */
// This a class rather than a struct so we get pass-by-reference
// semantics for it, and make its members private
public class Geary.Logging.State {


    public Source source { get; private set; }


    private string message;
    // Would like to use the following but can't because of
    // https://gitlab.gnome.org/GNOME/vala/issues/884
    // private va_list args;


    /*
     * Constructs a new logging state.
     *
     * The given source should be the source object that constructed
     * the state during a call to {@link Source.to_logging_state}.
     */
    [PrintfFormat]
    public State(Source source, string message, ...) {
        this.source = source;
        this.message = message;

        // this.args = va_list();
        this.message = message.vprintf(va_list());
    }

    public string format_message() {
        // vprint mangles its passed-in args, so copy them
        // return this.message.vprintf(va_list.copy(this.args));
        return message;
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
public class Geary.Logging.Record {


    /** The GLib domain of the log message, if any. */
    public string? domain { get; private set; default = null; }

    /** Account from which the record originated, if any. */
    public Account? account { get; private set; default = null; }

    /** Client service from which the record originated, if any. */
    public ClientService? service { get; private set; default = null; }

    /** Folder from which the record originated, if any. */
    public Folder? folder { get; private set; default = null; }

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
     * Copy constructor.
     *
     * Copies all properties of the given record except its next
     * record.
     */
    public Record.copy(Record other) {
        this.domain = other.domain;
        this.account = other.account;
        this.service = other.service;
        this.folder = other.folder;
        this.message = other.message;
        this.source_filename = other.source_filename;
        this.source_line_number = other.source_line_number;
        this.source_function = other.source_function;
        this.levels = other.levels;
        this.timestamp = other.timestamp;

        // Kept null deliberately so that we don't get a stack blowout
        // copying large record chains and code that does copy records
        // can copy only a fixed number.
        // this.next

        this.states = other.states;
        this.filled = other.filled;
        this.old_log_api = other.old_log_api;
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
        string message = this.message ?? "[no message]";
        double float_secs = this.timestamp / 1000.0 / 1000.0;
        double floor_secs = GLib.Math.floor(float_secs);
        int ms = (int) GLib.Math.round((float_secs - floor_secs) * 1000.0);
        GLib.DateTime time = new GLib.DateTime.from_unix_utc(
            (int64) float_secs
        ).to_local();
        GLib.StringBuilder str = new GLib.StringBuilder.sized(128);
        str.printf(
            "%s %02d:%02d:%02d.%04d %s:",
            to_prefix(levels),
            time.get_hour(),
            time.get_minute(),
            time.get_second(),
            ms,
            domain
        );

        // Append in reverse so inner sources appear first
        for (int i = this.states.length - 1; i >= 0; i--) {
            str.append(" [");
            str.append(this.states[i].format_message());
            str.append("]");
        }

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
        } else if (this.states.length > 0) {
            // Print the class name of the leaf logging source to at
            // least give a general idea of where the message came
            // from.
            str.append(" ");
            str.append(this.states[0].source.get_type().name());
            str.append(": ");
        }

        str.append(message);

        return str.str;
    }

}
