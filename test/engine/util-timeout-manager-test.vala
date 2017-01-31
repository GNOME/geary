/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.TimeoutManagerTest : Gee.TestCase {

    // add_seconds seems to vary wildly, so needs a large epsilon
    private const double SECONDS_EPSILON = 1.8;

    public TimeoutManagerTest() {
        base("Geary.TimeoutManagerTest");
        add_test("start_reset", start_reset);
        if (Test.slow()) {
            add_test("test_seconds", test_seconds);
            add_test("test_repeat_forever", test_repeat_forever);
        }
    }

    public void start_reset() {
        TimeoutManager test = new TimeoutManager.seconds(1, () => { /* noop */ });
        assert(!test.is_running);
        test.start();
        assert(test.is_running);
        test.reset();
        assert(!test.is_running);
    }

    public void test_seconds() {
        Timer timer = new Timer();

        TimeoutManager test = new TimeoutManager.seconds(1, () => { timer.stop(); });
        test.start();

        timer.start();
        while (test.is_running && timer.elapsed() < SECONDS_EPSILON) {
            Gtk.main_iteration();
        }

        assert_epsilon(timer.elapsed(), 1.0, SECONDS_EPSILON);
    }

    public void test_repeat_forever() {
        Timer timer = new Timer();
        int count = 0;

        TimeoutManager test = new TimeoutManager.seconds(1, () => { count++; });
        test.repetition = TimeoutManager.Repeat.FOREVER;
        test.start();

        timer.start();
        while (count < 2 && timer.elapsed() < SECONDS_EPSILON * 2) {
            Gtk.main_iteration();
        }
        timer.stop();

        assert_epsilon(timer.elapsed(), 2.0, SECONDS_EPSILON * 2);
    }

    private inline void assert_epsilon(double actual, double expected, double epsilon) {
        assert(actual + epsilon >= expected && actual - epsilon <= expected);
    }

}
