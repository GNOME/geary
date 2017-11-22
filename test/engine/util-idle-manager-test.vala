/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.IdleManagerTest : Gee.TestCase {

    public IdleManagerTest() {
        base("Geary.IdleManagerTest");
        add_test("start_reset", start_reset);
        add_test("test_run", test_run);
    }

    public void start_reset() {
        IdleManager test = new IdleManager(() => { /* noop */ });
        assert(!test.is_running);
        test.schedule();
        assert(test.is_running);
        test.reset();
        assert(!test.is_running);
    }

    public void test_run() {
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
