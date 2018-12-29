/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
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
        GLib.StringBuilder message = new GLib.StringBuilder(fmt);
        Loggable? decorator = this;
        while (decorator != null) {
            message.prepend_c(' ');
            message.prepend(decorator.to_string());
            decorator = decorator.loggable_parent;
        }

        Logging.logv(flags, levels, message.str, args);
    }

}
