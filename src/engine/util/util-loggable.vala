/*
 * Copyright 2018-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Mixin interface for objects that support structured logging.
 *
 * Loggable objects provide both a standard means to obtain a string
 * representation of the object for display to humans, and keep a weak
 * reference to some parent loggable, enabling this context to be
 * automatically added to logging calls. For example, if a Foo object
 * is the loggable parent of a Bar object, log calls made by Bar will
 * automatically be decorated with Foo.
 */
public interface Geary.Loggable : GLib.Object {


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

        public inline void append_loggable(Loggable value) {
            this.append("GEARY_LOGGABLE", value);
        }

        public GLib.LogField[] to_array() {
            // MESSAGE must always be last, so append it here
            append("MESSAGE", this.message);
            return this.fields[0:this.count];
        }

    }


    /**
     * Default flags to use for this loggable when logging messages.
     */
    public abstract Logging.Flag loggable_flags { get; protected set; }

    /**
     * The parent of this loggable.
     *
     * If not null, the parent and its ancestors recursively will be
     * added to to log message context.
     */
    public abstract Loggable? loggable_parent { get; }

    /**
     * Returns a string representation of the service, for debugging.
     */
    public abstract string to_string();


    /**
     * Logs a debug-level log message with this object as context.
     */
    [PrintfFormat]
    public inline void debug(string fmt, ...) {
        log_structured(
            this.loggable_flags, LogLevelFlags.LEVEL_DEBUG, fmt, va_list()
        );
    }

    /**
     * Logs a message-level log message with this object as context.
     */
    [PrintfFormat]
    public inline void message(string fmt, ...) {
        log_structured(
            this.loggable_flags, LogLevelFlags.LEVEL_MESSAGE, fmt, va_list()
        );
    }

    /**
     * Logs a warning-level log message with this object as context.
     */
    [PrintfFormat]
    public inline void warning(string fmt, ...) {
        log_structured(
            this.loggable_flags, LogLevelFlags.LEVEL_WARNING, fmt, va_list()
        );
    }

    /**
     * Logs a error-level log message with this object as context.
     */
    [PrintfFormat]
    [NoReturn]
    public inline void error(string fmt, ...) {
        log_structured(
            this.loggable_flags, LogLevelFlags.LEVEL_ERROR, fmt, va_list()
        );
    }

    /**
     * Logs a critical-level log message with this object as context.
     */
    [PrintfFormat]
    public inline void critical(string fmt, ...) {
        log_structured(
            this.loggable_flags, LogLevelFlags.LEVEL_CRITICAL, fmt, va_list()
        );
    }

    private inline void log_structured(Logging.Flag flags,
                                       GLib.LogLevelFlags levels,
                                       string fmt,
                                       va_list args) {
        Context context = Context(Logging.DOMAIN, flags, levels, fmt, args);
        Loggable? decorated = this;
        while (decorated != null) {
            context.append_loggable(decorated);
            decorated = decorated.loggable_parent;
        }

        GLib.log_structured_array(levels, context.to_array());
    }

}
