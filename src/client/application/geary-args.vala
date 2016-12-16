/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Args {

private const OptionEntry[] options = {
    { "hidden", 0, 0, OptionArg.NONE, ref hidden_startup, N_("Start Geary with hidden main window"), null },
    { "debug", 'd', 0, OptionArg.NONE, ref log_debug, N_("Output debugging information"), null },
    { "log-conversations", 0, 0, OptionArg.NONE, ref log_conversations, N_("Log conversation monitoring"), null },
    { "log-deserializer", 0, 0, OptionArg.NONE, ref log_deserializer, N_("Log network deserialization"), null },
    { "log-network", 0, 0, OptionArg.NONE, ref log_network, N_("Log network activity"), null },
    /// The IMAP replay queue is how changes on the server are replicated on the client.
    /// It could also be called the IMAP events queue.
    { "log-replay-queue", 0, 0, OptionArg.NONE, ref log_replay_queue, N_("Log IMAP replay queue"), null },
    /// Serialization is how commands and responses are converted into a stream of bytes for
    /// network transmission
    { "log-serializer", 0, 0, OptionArg.NONE, ref log_serializer, N_("Log network serialization"), null },
    { "log-periodic", 0, 0, OptionArg.NONE, ref log_periodic, N_("Log periodic activity"), null },
    { "log-sql", 0, 0, OptionArg.NONE, ref log_sql, N_("Log database queries (generates lots of messages)"), null },
    /// "Normalization" can also be called "synchronization"
    { "log-folder-normalization", 0, 0, OptionArg.NONE, ref log_folder_normalization, N_("Log folder normalization"), null },
    { "inspector", 'i', 0, OptionArg.NONE, ref inspector, N_("Allow inspection of WebView"), null },
    { "revoke-certs", 0, 0, OptionArg.NONE, ref revoke_certs, N_("Revoke all server certificates with TLS warnings"), null },
    { "quit", 'q', 0, OptionArg.NONE, ref quit, N_("Perform a graceful quit"), null },
    { "version", 'V', 0, OptionArg.NONE, ref version, N_("Display program version"), null },
    { null }
};

public bool hidden_startup = false;
public bool log_debug = false;
public bool log_network = false;
public bool log_serializer = false;
public bool log_deserializer = false;
public bool log_replay_queue = false;
public bool log_conversations = false;
public bool log_periodic = false;
public bool log_sql = false;
public bool log_folder_normalization = false;
public bool inspector = false;
public bool quit = false;
public bool revoke_certs = false;
public bool version = false;

public bool parse(string[] args) {
    var context = new OptionContext("[%s...]".printf(Geary.ComposedEmail.MAILTO_SCHEME));
    context.set_help_enabled(true);
    context.add_main_entries(options, null);
    context.set_description("%s\n\n%s\n\n%s\n\t%s\n".printf(
        // This gives a command-line hint on how to open new composer windows with mailto:
        _("Use %s to open a new composer window").printf(Geary.ComposedEmail.MAILTO_SCHEME),
        GearyApplication.COPYRIGHT, _("Please report comments, suggestions and bugs to:"),
        GearyApplication.BUGREPORT));
    
    try {
        context.parse(ref args);
    } catch (OptionError error) {
        // i18n: Command line arguments are invalid
        stdout.printf (_("Failed to parse command line options: %s\n"), error.message);
        stdout.printf("\n%s", context.get_help(true, null));
        return false;
    }
    
    // other than the OptionEntry command-line arguments, the only acceptable arguments are
    // mailto:'s
    for (int ctr = 1; ctr < args.length; ctr++) {
        string arg = args[ctr];
        
        if (!arg.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)) {
            stdout.printf(_("Unrecognized command line option “%s”\n").printf(arg));
            stdout.printf("\n%s", context.get_help(true, null));
            
            return false;
        }
    }
    
    if (version) {
        stdout.printf("%s %s\n", GearyApplication.PRGNAME, GearyApplication.VERSION);
        Process.exit(0);
    }
    
    if (log_network)
        Geary.Logging.enable_flags(Geary.Logging.Flag.NETWORK);
    
    if (log_serializer)
        Geary.Logging.enable_flags(Geary.Logging.Flag.SERIALIZER);
    
    if (log_replay_queue)
        Geary.Logging.enable_flags(Geary.Logging.Flag.REPLAY);
    
    if (log_conversations)
        Geary.Logging.enable_flags(Geary.Logging.Flag.CONVERSATIONS);
    
    if (log_periodic)
        Geary.Logging.enable_flags(Geary.Logging.Flag.PERIODIC);
    
    if (log_sql)
        Geary.Logging.enable_flags(Geary.Logging.Flag.SQL);
    
    if (log_folder_normalization)
        Geary.Logging.enable_flags(Geary.Logging.Flag.FOLDER_NORMALIZATION);
    
    if (log_deserializer)
        Geary.Logging.enable_flags(Geary.Logging.Flag.DESERIALIZER);
    
    if (log_debug)
        Geary.Logging.log_to(stdout);
    
    return true;
}

}

