/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


int main(string[] args) {
    GLib.Test.init(ref args);
    Geary.RFC822.init();
    Geary.HTML.init();
    Geary.Logging.init();
    if (GLib.Test.verbose()) {
        GLib.Log.set_writer_func(Geary.Logging.default_log_writer);
        Geary.Logging.log_to(GLib.stdout);
    }

    GLib.TestSuite root = GLib.TestSuite.get_root();
    root.add_suite(new MailMerge.TestReader().suite);
    root.add_suite(new MailMerge.TestProcessor().suite);

    GLib.MainLoop loop = new GLib.MainLoop();
    int ret = -1;
    GLib.Idle.add(() => {
            ret = Test.run();
            loop.quit();
            return false;
        });

    loop.run();
    return ret;
}
