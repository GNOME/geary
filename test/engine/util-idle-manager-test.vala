/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.IdleManagerTest : TestCase {


    private class WeakRefTest : GLib.Object {

        public IdleManager test { get; private set; }

        public WeakRefTest() {
            // Pass in an arg to ensure the closure is non-trivial
            string arg = "my hovercraft is full of eels";
            this.test = new IdleManager(
                () => {
                    do_stuff(arg);
                }
            );

            // Pass
            this.test.schedule();
        }

        private void do_stuff(string arg) {
            // This should never get called
            GLib.assert(false);
        }

    }


    public IdleManagerTest() {
        base("Geary.IdleManagerTest");
        add_test("weak_ref", callback_weak_ref);
        add_test("start_reset", start_reset);
        add_test("test_run", test_run);
    }

    public void callback_weak_ref() throws GLib.Error {
        WeakRefTest? owner = new WeakRefTest();
        GLib.WeakRef weak_ref = GLib.WeakRef(owner.test);

        // Should make both objects null even though the even loop
        // hasn't run and hence the callback hasn't been called.
        owner = null;
        assert_null(weak_ref.get());

        // Pump the loop a few times so the callback can get called.
        this.main_loop.iteration(false);
        this.main_loop.iteration(false);
    }

    public void start_reset() throws Error {
        IdleManager test = new IdleManager(() => { /* noop */ });
        assert(!test.is_running);
        test.schedule();
        assert(test.is_running);
        test.reset();
        assert(!test.is_running);
    }

    public void test_run() throws Error {
        bool did_run = false;

        IdleManager test = new IdleManager(() => { did_run = true; });
        test.schedule();

        // There should be at least one event pending
        assert(this.main_loop.pending());

        // Execute the idle function
        this.main_loop.iteration(true);

        assert(did_run);
    }

}
