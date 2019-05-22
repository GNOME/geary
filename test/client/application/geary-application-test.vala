/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


class GearyApplicationTest : TestCase {


    private GearyApplication? test_article = null;


    public GearyApplicationTest() {
        base("GearyApplicationTest");
        add_test("paths_when_installed", paths_when_installed);
    }

    public override void set_up() {
        this.test_article = new GearyApplication();
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

        assert_string(
            _INSTALL_PREFIX + "/share/geary",
            this.test_article.get_resource_directory().get_path()
        );
        assert_string(
            _INSTALL_PREFIX + "/share/applications",
            this.test_article.get_desktop_directory().get_path()
        );
    }

}
