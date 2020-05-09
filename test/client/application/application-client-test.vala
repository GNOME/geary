/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


class Application.ClientTest : TestCase {


    private Client? test_article = null;


    public ClientTest() {
        base("Application.ClientTest");
        add_test("paths_when_installed", paths_when_installed);
    }

    public override void set_up() {
        this.test_article = new Client();
    }

    public override void tear_down() {
        this.test_article = null;
    }

    public void paths_when_installed() throws GLib.Error {
        string[] args = new string[] {
            _INSTALL_PREFIX + "/bin/geary",
            // Specify this so the app doesn't actually attempt
            // to start up
            "-v"
        };
        unowned string[] unowned_args = args;
        int status;
        this.test_article.local_command_line(ref unowned_args, out status);

        assert_equal(
            this.test_article.get_resource_directory().get_path(),
            _INSTALL_PREFIX + "/share/geary"
        );
        assert_equal(
            this.test_article.get_desktop_directory().get_path(),
            _INSTALL_PREFIX + "/share/applications"
        );
    }

}
