/*
 * Copyright © 2009 Julien Peeters
 * Copyright © 2017-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 *
 * Author(s):
 *  Julien Peeters <contact@julienpeeters.fr>
 *  Michael Gratton <mike@vee.net>
 */


/**
 * A ValaUnit to GLib testing framework adaptor.
 */
internal class ValaUnit.TestAdaptor : GLib.Object {


    public string name { get; private set; }
    public TestCase test_case { get; private set; }

    private TestCase.TestMethod test;


    public TestAdaptor(string name,
                       owned TestCase.TestMethod test,
                       TestCase test_case) {
        this.name = name;
        this.test = (owned) test;
        this.test_case = test_case;
    }

    public void set_up(void* fixture) {
        try {
            this.test_case.set_up();
        } catch (GLib.Error err) {
            log_error(err);
            GLib.assert_not_reached();
        }
    }

    public void run(void* fixture) {
        try {
            this.test();
        } catch (TestError.SKIPPED err) {
            GLib.Test.skip(err.message);
        } catch (GLib.Error err) {
            log_error(err);
            GLib.Test.fail();
        }
    }

    public void tear_down(void* fixture) {
        try {
            this.test_case.tear_down();
        } catch (Error err) {
            log_error(err);
            GLib.assert_not_reached();
        }
    }

    private void log_error(GLib.Error err) {
        GLib.stderr.puts(this.test_case.name);
        GLib.stderr.putc('/');

        GLib.stderr.puts(this.name);
        GLib.stderr.puts(": ");

        GLib.stderr.puts(err.message);
        GLib.stderr.putc('\n');
        GLib.stderr.flush();
    }

}
