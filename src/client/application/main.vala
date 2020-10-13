/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

int main(string[] args) {
    // Init logging right up front so as to capture as many log
    // messages as possible
    Geary.Logging.init();
    GLib.Log.set_writer_func(Geary.Logging.default_log_writer);

    Application.Client app = new Application.Client();

    int ec = app.run(args);

#if REF_TRACKING
    Geary.BaseObject.dump_refs(stdout);
#endif

    return ec;
}
