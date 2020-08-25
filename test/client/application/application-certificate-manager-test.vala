/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


class Application.CertificateManagerTest : TestCase {


    private const string IDENITY_HOSTNAME = "localhost";
    private const uint16 IDENITY_PORT = 143;

    private static int cert_id = 1;

    private GLib.File? tmp = null;
    private GLib.File? db_dir = null;
    private GLib.File? cert_dir = null;


    public CertificateManagerTest() {
        base("Application.CertificateManagerTest");
        add_test(
            "database_memory_certificate_pinning_without_gcr",
            database_memory_certificate_pinning_without_gcr
        );
        add_test(
            "database_disk_certificate_pinning_without_gcr",
            database_disk_certificate_pinning_without_gcr
        );
    }

    public override void set_up() throws GLib.Error {
        this.tmp = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("application-certificate-manager-test-XXXXXX")
        );
        this.db_dir = this.tmp.get_child("db");
        this.db_dir.make_directory();
        this.cert_dir = this.tmp.get_child("certs");
        this.cert_dir.make_directory();
    }

    public override void tear_down() throws GLib.Error {
        delete_file(this.tmp);
        this.db_dir = null;
        this.cert_dir = null;
        this.tmp = null;
    }

    public void database_memory_certificate_pinning_without_gcr()
        throws GLib.Error {
        var test_article1 = new Application.TlsDatabase(
            GLib.TlsBackend.get_default().get_default_database(),
            this.db_dir,
            false
        );
        var id = new_identity();
        var cert1 = new_cert("cert1");
        var cert2 = new_cert("cert2");

        // Assert the db doesn't know about the cert first up.
        assert_pinning(test_article1, cert1, id, false);
        assert_pinning(test_article1, cert2, id, false);

        // Pin a cert in the db
        test_article1.pin_certificate.begin(
            cert1, id, false, null, this.async_completion
        );
        test_article1.pin_certificate.end(this.async_result());

        // Assert the db now knows about it, but not the other
        assert_pinning(test_article1, cert1, id, true);
        assert_pinning(test_article1, cert2, id, false);

        // Construct a new test article and ensure it doesn't know
        // about either
        var test_article2 = new Application.TlsDatabase(
            GLib.TlsBackend.get_default().get_default_database(),
            this.db_dir,
            false
        );
        assert_pinning(test_article2, cert1, id, false);
        assert_pinning(test_article2, cert2, id, false);
    }

    public void database_disk_certificate_pinning_without_gcr()
        throws GLib.Error {
        var test_article1 = new Application.TlsDatabase(
            GLib.TlsBackend.get_default().get_default_database(),
            this.db_dir,
            false
        );
        var id = new_identity();
        var cert1 = new_cert("cert1");
        var cert2 = new_cert("cert2");

        // Assert the db doesn't know about the cert first up.
        assert_pinning(test_article1, cert1, id, false);
        assert_pinning(test_article1, cert2, id, false);

        // Pin a cert in the db
        test_article1.pin_certificate.begin(
            cert1, id, true, null, this.async_completion
        );
        test_article1.pin_certificate.end(this.async_result());

        // Assert the db now knows about it, but not the other
        assert_pinning(test_article1, cert1, id, true);
        assert_pinning(test_article1, cert2, id, false);

        // Construct a new test article and ensure it has loaded the
        // first from disk
        var test_article2 = new Application.TlsDatabase(
            GLib.TlsBackend.get_default().get_default_database(),
            this.db_dir,
            false
        );
        assert_pinning(test_article2, cert1, id, true);
        assert_pinning(test_article2, cert2, id, false);
    }

    private void assert_pinning(Application.TlsDatabase db,
                                GLib.TlsCertificate cert,
                                GLib.SocketConnectable id,
                                bool is_pinned)
        throws GLib.Error {
        // Test both the sync and async calls to ensure equivalence
        var sync_ret = db.verify_chain(
            cert,
            GLib.TlsDatabase.PURPOSE_AUTHENTICATE_SERVER,
            id,
            null,
            NONE,
            null
        );
        if (is_pinned) {
            assert_true(
                sync_ret == 0,
                "is pinned sync"
            );
        } else {
            assert_true(
                sync_ret == GLib.TlsCertificateFlags.UNKNOWN_CA,
                "not pinned sync"
            );
        }

        db.verify_chain_async.begin(
            cert,
            GLib.TlsDatabase.PURPOSE_AUTHENTICATE_SERVER,
            id,
            null,
            NONE,
            null,
            this.async_completion
        );
        var async_ret = db.verify_chain_async.end(this.async_result());
        if (is_pinned) {
            assert_true(
                async_ret == 0,
                "is pinned async"
            );
        } else {
            assert_true(
                async_ret == GLib.TlsCertificateFlags.UNKNOWN_CA,
                "not pinned async"
            );
        }
    }

    private GLib.SocketConnectable new_identity() {
        return new GLib.NetworkAddress(IDENITY_HOSTNAME, IDENITY_PORT);
    }

    private GLib.TlsCertificate new_cert(string name) throws GLib.Error {
        var priv_name = name + ".priv";
        var cert_name = name + ".cert";
        var template_name = name + ".template";
        GLib.Process.spawn_sync(
            this.cert_dir.get_path(),
            {
                "certtool", "--generate-privkey", "--outfile", priv_name
            },
            GLib.Environ.get(),
            SpawnFlags.SEARCH_PATH,
            null
        );
        this.cert_dir.get_child(template_name).create(NONE).write("""
organization = "Example Inc."
country = AU
serial = %d
expiration_days = 1
dns_name = "%s"
encryption_key
""".printf(CertificateManagerTest.cert_id++, IDENITY_HOSTNAME).data);

        GLib.Process.spawn_sync(
            this.cert_dir.get_path(),
            {
                "certtool",
                    "--generate-self-signed",
                    "--load-privkey", priv_name,
                    "--template", template_name,
                    "--outfile", cert_name
            },
            GLib.Environ.get(),
            SpawnFlags.SEARCH_PATH,
            null
        );
        return new GLib.TlsCertificate.from_file(
            this.cert_dir.get_child(cert_name).get_path()
        );
    }

}
