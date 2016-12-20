/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Args {

// LOCAL OPTIONS
public const string OPTION_VERSION = "version";
// GENERAL OPTIONS
public const string OPTION_LOG_DEBUG = "debug";
public const string OPTION_LOG_NETWORK = "log-conversations";
public const string OPTION_LOG_SERIALIZER = "log-deserializer";
public const string OPTION_LOG_DESERIALIZER = "log-network";
public const string OPTION_LOG_REPLAY_QUEUE = "log-replay-queue";
public const string OPTION_LOG_CONVERSATIONS = "log-serializer";
public const string OPTION_LOG_PERIODIC = "log-periodic";
public const string OPTION_LOG_SQL = "log-sql";
public const string OPTION_LOG_FOLDER_NORMALIZATION = "log-folder-normalization";
public const string OPTION_INSPECTOR = "inspector";
public const string OPTION_REVOKE_CERTS = "revoke-certs";
public const string OPTION_QUIT = "quit";

// This is also the order in which they are presented to the user, so it's probably best to keep
// them alphabetical
public const OptionEntry[] OPTION_ENTRIES = {
    { OPTION_LOG_DEBUG, 'd', 0, OptionArg.NONE, null, N_("Output debugging information"), null },
    { OPTION_INSPECTOR, 'i', 0, OptionArg.NONE, null, N_("Allow inspection of WebView"), null },
    { OPTION_LOG_CONVERSATIONS, 0, 0, OptionArg.NONE, null, N_("Log conversation monitoring"), null },
    { OPTION_LOG_DESERIALIZER, 0, 0, OptionArg.NONE, null, N_("Log network deserialization"), null },
    { OPTION_LOG_NETWORK, 0, 0, OptionArg.NONE, null, N_("Log network activity"), null },
    /// The IMAP replay queue is how changes on the server are replicated on the client.
    /// It could also be called the IMAP events queue.
    { OPTION_LOG_REPLAY_QUEUE, 0, 0, OptionArg.NONE, null, N_("Log IMAP replay queue"), null },
    /// Serialization is how commands and responses are converted into a stream of bytes for
    /// network transmission
    { OPTION_LOG_SERIALIZER, 0, 0, OptionArg.NONE, null, N_("Log network serialization"), null },
    { OPTION_LOG_PERIODIC, 0, 0, OptionArg.NONE, null, N_("Log periodic activity"), null },
    { OPTION_LOG_SQL, 0, 0, OptionArg.NONE, null, N_("Log database queries (generates lots of messages)"), null },
    /// "Normalization" can also be called "synchronization"
    { OPTION_LOG_FOLDER_NORMALIZATION, 0, 0, OptionArg.NONE, null, N_("Log folder normalization"), null },
    { OPTION_REVOKE_CERTS, 0, 0, OptionArg.NONE, null, N_("Revoke all server certificates with TLS warnings"), null },
    { OPTION_VERSION, 'V', 0, OptionArg.NONE, null, N_("Display program version"), null },
    { OPTION_QUIT, 'q', 0, OptionArg.NONE, null, N_("Perform a graceful quit"), null },
    /// Use this to specify arguments in the help section
    { "", 0, 0, OptionArg.NONE, null, null, "[mailto:...]" },
    { null }
};

/**
  * Handles options for a locally running instance, i.e. options for which you don't need to make
  * a connection to a service instance that is already running.
  */
public int handle_local_options(VariantDict local_options) {
    if (local_options.contains(OPTION_VERSION)) {
        stdout.printf("%s %s\n", Environment.get_prgname(), GearyApplication.VERSION);
        return 0;
    }

    return -1;
}

public int handle_general_options(Configuration config, VariantDict options) {
    if (options.contains(OPTION_QUIT))
        return 0;

    bool enable_debug = options.contains(OPTION_LOG_DEBUG);
    // Will be logging to stderr until this point
    if (enable_debug) {
        Geary.Logging.log_to(stdout);
    } else {
        Geary.Logging.log_to(null);
    }

    // Logging flags
    if (options.contains(OPTION_LOG_NETWORK))
        Geary.Logging.enable_flags(Geary.Logging.Flag.NETWORK);
    if (options.contains(OPTION_LOG_SERIALIZER))
        Geary.Logging.enable_flags(Geary.Logging.Flag.SERIALIZER);
    if (options.contains(OPTION_LOG_REPLAY_QUEUE))
        Geary.Logging.enable_flags(Geary.Logging.Flag.REPLAY);
    if (options.contains(OPTION_LOG_CONVERSATIONS))
        Geary.Logging.enable_flags(Geary.Logging.Flag.CONVERSATIONS);
    if (options.contains(OPTION_LOG_PERIODIC))
        Geary.Logging.enable_flags(Geary.Logging.Flag.PERIODIC);
    if (options.contains(OPTION_LOG_SQL))
        Geary.Logging.enable_flags(Geary.Logging.Flag.SQL);
    if (options.contains(OPTION_LOG_FOLDER_NORMALIZATION))
        Geary.Logging.enable_flags(Geary.Logging.Flag.FOLDER_NORMALIZATION);
    if (options.contains(OPTION_LOG_DESERIALIZER))
        Geary.Logging.enable_flags(Geary.Logging.Flag.DESERIALIZER);

    config.enable_debug = enable_debug;
    config.enable_inspector = options.contains(OPTION_INSPECTOR);
    config.revoke_certs = options.contains(OPTION_REVOKE_CERTS);

    return -1;
}

/**
  * Handles the actual arguments of the application.
  */
public int handle_arguments(GearyApplication app, string[] args) {
    for (int ctr = 1; ctr < args.length; ctr++) {
        string arg = args[ctr];

        // the only acceptable arguments are mailto:'s
        if (arg.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)) {
            if (arg == Geary.ComposedEmail.MAILTO_SCHEME)
                app.activate_action(GearyApplication.ACTION_COMPOSE, null);
            else
                app.activate_action(GearyApplication.ACTION_MAILTO, new Variant.string(arg));
        } else {
            stdout.printf(_("Unrecognized argument: “%s”\n").printf(arg));
            stdout.printf(_("Geary only accepts mailto-links as arguments.\n"));

            return 1;
        }
    }

    return -1;
}

}
