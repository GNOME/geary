/* testcase.vala
 *
 * Copyright (C) 2009 Julien Peeters
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.

 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.

 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 * Author:
 * 	Julien Peeters <contact@julienpeeters.fr>
 * 	Michael Gratton <mike@vee.net>
 */

public abstract class Gee.TestCase : Object {

	private GLib.TestSuite suite;
	private Adaptor[] adaptors = new Adaptor[0];
    private AsyncQueue<AsyncResult> async_results = new AsyncQueue<AsyncResult>();

	public delegate void TestMethod ();

	public TestCase (string name) {
		this.suite = new GLib.TestSuite (name);
	}

	public void add_test (string name, owned TestMethod test) {
		var adaptor = new Adaptor (name, (owned)test, this);
		this.adaptors += adaptor;

		this.suite.add (new GLib.TestCase (adaptor.name,
		                                   adaptor.set_up,
		                                   adaptor.run,
		                                   adaptor.tear_down ));
	}

	public virtual void set_up () {
	}

	public virtual void tear_down () {
	}

	public GLib.TestSuite get_suite () {
		return this.suite;
	}

    protected void async_complete(AsyncResult result) {
        this.async_results.push(result);
    }

    protected AsyncResult async_result() {
        AsyncResult? result = null;
        while (result == null) {
            Gtk.main_iteration();
            result = this.async_results.try_pop();
        }
        return result;
    }

	private class Adaptor {
		[CCode (notify = false)]
		public string name { get; private set; }
		private TestMethod test;
		private TestCase test_case;

		public Adaptor (string name,
		                owned TestMethod test,
		                TestCase test_case) {
			this.name = name;
			this.test = (owned)test;
			this.test_case = test_case;
		}

		public void set_up (void* fixture) {
			this.test_case.set_up ();
		}

		public void run (void* fixture) {
			this.test ();
		}

		public void tear_down (void* fixture) {
			this.test_case.tear_down ();
		}
	}
}
