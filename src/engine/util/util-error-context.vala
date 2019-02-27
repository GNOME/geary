/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Provides additional context information for an error when thrown.
 *
 * This class allows the engine to provide additional context
 * information such as stack traces, the cause of this error, or
 * engine state when an error is thrown. A stack trace will be
 * generated for the context when instantiated, so context instances
 * should be constructed as close to when the error was thrown as
 * possible.
 *
 * This works around the GLib error system's lack of extensibility.
 */
public class Geary.ErrorContext : BaseObject {


    /** Represents an individual stack frame in a call back-trace. */
    public class StackFrame {


        /** Name of the function being called. */
        public string name = "unknown";


#if HAVE_LIBUNWIND
        internal StackFrame(Unwind.Cursor frame) {
            uint8 proc_name[256];
            int ret = -frame.get_proc_name(proc_name);
            if (ret == Unwind.Error.SUCCESS ||
                ret == Unwind.Error.NOMEM) {
                this.name = (string) proc_name;
            }
        }
#endif

        public string to_string() {
            return this.name;
        }

    }


    /** The error thrown that this context is describing. */
    public GLib.Error thrown { get; private set; }

    /** A back trace from when the context was constructed. */
    public Gee.List<StackFrame>? backtrace {
        get; private set; default = new Gee.LinkedList<StackFrame>();
    }


    public ErrorContext(GLib.Error thrown) {
        this.thrown = thrown;

#if HAVE_LIBUNWIND
        Unwind.Context trace = Unwind.Context();
        Unwind.Cursor cursor = Unwind.Cursor.local(trace);

        // This misses the first frame, but that's this
        // constructor call, so we don't really care.
        while (cursor.step() != 0) {
            this.backtrace.add(new StackFrame(cursor));
        }
#endif
    }

    /** Returns a string representation of the error type, for debugging. */
    public string? format_error_type() {
        string type = null;
        if (this.thrown != null) {
            const string QUARK_SUFFIX = "-quark";
            string ugly_domain = this.thrown.domain.to_string();
            if (ugly_domain.has_suffix(QUARK_SUFFIX)) {
                ugly_domain = ugly_domain.substring(
                    0, ugly_domain.length - QUARK_SUFFIX.length
                );
            }
            StringBuilder nice_domain = new StringBuilder();
            string separator = (ugly_domain.index_of("_") != -1) ? "_" : "-";
            foreach (string part in ugly_domain.split(separator)) {
                if (part.length > 0) {
                    if (part == "io") {
                        nice_domain.append("IO");
                    } else {
                        nice_domain.append(part.up(1));
                        nice_domain.append(part.substring(1));
                    }
                }
            }

            type = "%s %i".printf(nice_domain.str, this.thrown.code);
        }
        return type;
    }

    /** Returns a string representation of the complete error, for debugging. */
    public string? format_full_error() {
        string error = null;
        if (this.thrown != null) {
            error = String.is_empty(this.thrown.message)
                ? "%s: no message specified".printf(format_error_type())
                : "%s: \"%s\"".printf(
                    format_error_type(), this.thrown.message
                );
        }
        return error;
    }

}
