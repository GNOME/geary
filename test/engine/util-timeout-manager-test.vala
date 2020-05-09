/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.TimeoutManagerTest : TestCase {

    // add_seconds seems to vary wildly, so needs a large epsilon
    private const double SECONDS_EPSILON = 1.8;

    private const double MILLISECONDS_EPSILON = 0.1;


    private class WeakRefTest : GLib.Object {

        public TimeoutManager test { get; private set; }

        public WeakRefTest() {            // Pass in an arg to ensure the closure is non-trivial
            string arg = "my hovercraft is full of eels";
            this.test = new TimeoutManager.milliseconds(
                10, () => {
                    do_stuff(arg);
                }
            );

            // Pass
            this.test.start();
        }

        private void do_stuff(string arg) {
            // This should never get called
            GLib.assert(false);
        }

    }


    public TimeoutManagerTest() {
        base("Geary.TimeoutManagerTest");
        add_test("weak_ref", callback_weak_ref);
        add_test("start_reset", start_reset);
        if (Test.slow()) {
            add_test("seconds", seconds);
            add_test("milliseconds", milliseconds);
            add_test("repeat_forever", repeat_forever);
        }
    }

    public void callback_weak_ref() throws GLib.Error {
        WeakRefTest? owner = new WeakRefTest();
        double duration = owner.test.interval;
        GLib.WeakRef weak_ref = GLib.WeakRef(owner.test);

        // Should make both objects null even though the even loop
        // hasn't run and hence the callback hasn't been called.
        owner = null;
        assert_null(weak_ref.get());

        // Pump the loop until the timeout has passed so that the
        // callback can get called.
        Timer timer = new Timer();
        timer.start();
        while (timer.elapsed() < (duration / 1000) * 2) {
            this.main_loop.iteration(false);
        }
    }

    public void start_reset() throws Error {
        TimeoutManager test = new TimeoutManager.seconds(1, () => { /* noop */ });
        assert(!test.is_running);
        test.start();
        assert(test.is_running);
        test.reset();
        assert(!test.is_running);
    }

    public void seconds() throws Error {
        Timer timer = new Timer();

        TimeoutManager test = new TimeoutManager.seconds(1, () => { timer.stop(); });
        test.start();

        timer.start();
        while (test.is_running && timer.elapsed() < SECONDS_EPSILON) {
            this.main_loop.iteration(true);
        }

        assert_within(timer.elapsed(), 1.0, SECONDS_EPSILON);
    }

    public void milliseconds() throws Error {
        Timer timer = new Timer();

        TimeoutManager test = new TimeoutManager.milliseconds(100, () => { timer.stop(); });
        test.start();

        timer.start();
        while (test.is_running && timer.elapsed() < 100 + MILLISECONDS_EPSILON) {
            this.main_loop.iteration(true);
        }

        assert_within(timer.elapsed(), 0.1, MILLISECONDS_EPSILON);
    }

    public void repeat_forever() throws Error {
        Timer timer = new Timer();
        int count = 0;

        TimeoutManager test = new TimeoutManager.seconds(1, () => { count++; });
        test.repetition = TimeoutManager.Repeat.FOREVER;
        test.start();

        timer.start();
        while (count < 2 && timer.elapsed() < SECONDS_EPSILON * 2) {
            this.main_loop.iteration(true);
        }
        timer.stop();

        assert_within(timer.elapsed(), 2.0, SECONDS_EPSILON * 2);
    }

}
