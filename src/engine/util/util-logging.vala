/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2018-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


namespace Geary.Logging {


    internal Gee.Set<string> suppressed_domains;


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
                Logging.Flag flags,
                GLib.LogLevelFlags level,
                string message,
                va_list args) {
            this.fields = new GLib.LogField[FIELD_COUNT];
            this.len = FIELD_COUNT;
            this.count = 0;
            append("PRIORITY", log_level_to_priority(level));
            append("GLIB_DOMAIN", domain);
            append("GEARY_FLAGS", flags);

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
     * Default flags to use for this source when logging messages.
     */
    public abstract Logging.Flag logging_flags { get; protected set; }

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
            log_structured(
                this.logging_flags, LogLevelFlags.LEVEL_DEBUG, fmt, va_list()
            );
        }
    }

    /**
     * Logs a message-level log message with this object as context.
     */
    [PrintfFormat]
    public inline void message(string fmt, ...) {
        log_structured(
            this.logging_flags, LogLevelFlags.LEVEL_MESSAGE, fmt, va_list()
        );
    }

    /**
     * Logs a warning-level log message with this object as context.
     */
    [PrintfFormat]
    public inline void warning(string fmt, ...) {
        log_structured(
            this.logging_flags, LogLevelFlags.LEVEL_WARNING, fmt, va_list()
        );
    }

    /**
     * Logs a error-level log message with this object as context.
     */
    [PrintfFormat]
    [NoReturn]
    public inline void error(string fmt, ...) {
        log_structured(
            this.logging_flags, LogLevelFlags.LEVEL_ERROR, fmt, va_list()
        );
    }

    /**
     * Logs a critical-level log message with this object as context.
     */
    [PrintfFormat]
    public inline void critical(string fmt, ...) {
        log_structured(
            this.logging_flags, LogLevelFlags.LEVEL_CRITICAL, fmt, va_list()
        );
    }

    /**
     * Logs a message with this object as context.
     */
    [PrintfFormat]
    public inline void log(Logging.Flag flags,
                           GLib.LogLevelFlags levels,
                           string fmt, ...) {
        log_structured(flags, levels, fmt, va_list());
    }

    private inline void log_structured(Logging.Flag flags,
                                       GLib.LogLevelFlags levels,
                                       string fmt,
                                       va_list args) {
        if (flags == ALL || Logging.get_flags().is_any_set(flags)) {
            Context context = Context(
                this.logging_domain, flags, levels, fmt, args
            );
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
