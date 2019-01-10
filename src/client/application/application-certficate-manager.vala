/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */


// All of the below basically exists since cert pinning using GCR
// stopped working (GNOME/gcr#10) after gnome-keyring stopped
// advertising its PKCS11 module (GNOME/gnome-keyring#20). To work
// around, this piggy-backs off of the GIO infrastructure and adds a
// custom pinned cert store.

/** Errors thrown by {@link CertificateManager}. */
public errordomain Application.CertificateManagerError {

    /** The certificate was not trusted by the user. */
    UNTRUSTED,

    /** The certificate could not be saved. */
    STORE_FAILED;

}

/**
 * Managing TLS certificate prompting and storage.
 */
public class Application.CertificateManager : GLib.Object {


    private TlsDatabase? pinning_database;


    /**
     * Constructs a new instance, globally installing the pinning database.
     */
    public CertificateManager() {
        this.pinning_database = new TlsDatabase(
            GLib.TlsBackend.get_default().get_default_database()
        );
        Geary.Endpoint.default_tls_database = this.pinning_database;
    }

    /**
     * Destroys an instance, de-installs the pinning database.
     */
    ~CertificateManager() {
        Geary.Endpoint.default_tls_database = null;
    }


    /**
     * Prompts the user to trust the certificate for a service.
     *
     * Returns true if the user accepted the certificate.
     */
    public async void prompt_pin_certificate(Gtk.Window parent,
                                             Geary.AccountInformation account,
                                             Geary.ServiceInformation service,
                                             Geary.Endpoint endpoint,
                                             bool is_validation,
                                             GLib.Cancellable? cancellable)
        throws CertificateManagerError {
        CertificateWarningDialog dialog = new CertificateWarningDialog(
            parent, account, service, endpoint, is_validation
        );

        bool save = false;
        switch (dialog.run()) {
        case CertificateWarningDialog.Result.TRUST:
            // noop
            break;

        case CertificateWarningDialog.Result.ALWAYS_TRUST:
            save = true;
            break;

        default:
            throw new CertificateManagerError.UNTRUSTED("User declined");
        }

        debug("Pinning certificate for %s...", endpoint.remote.to_string());
        try {
            yield add_pinned(
                endpoint.untrusted_certificate,
                endpoint.remote,
                save,
                cancellable
            );
        } catch (GLib.Error err) {
            throw new CertificateManagerError.STORE_FAILED(err.message);
        }
    }

    private async void add_pinned(GLib.TlsCertificate cert,
                                  GLib.SocketConnectable? identity,
                                  bool save,
                                  GLib.Cancellable? cancellable)
        throws GLib.Error {
        this.pinning_database.pin_certificate(cert, identity);
        if (save) {
            // XXX
        }
    }

}


/** TLS database that observes locally pinned certs. */
private class Application.TlsDatabase : GLib.TlsDatabase {


    /** A certificate and the identities it is trusted for. */
    private class TrustContext : Geary.BaseObject {


        // Perform IO at high priority since UI and network
        // connections depend on it
        private const int IO_PRIO = GLib.Priority.HIGH;
        private const GLib.ChecksumType ID_TYPE = GLib.ChecksumType.SHA384;
        private const string FILENAME_FORMAT = "%s.pem";


        public string id;
        public GLib.TlsCertificate certificate;


        public TrustContext(GLib.TlsCertificate certificate) {
            this.id = GLib.Checksum.compute_for_data(
                ID_TYPE, certificate.certificate.data
            );
            this.certificate = certificate;
        }

    }


    private static string to_name(GLib.SocketConnectable id) {
        GLib.NetworkAddress? name = id as GLib.NetworkAddress;
        if (name != null) {
            return name.hostname;
        }

        GLib.NetworkService? service = id as GLib.NetworkService;
        if (service != null) {
            return service.domain;
        }

        GLib.InetSocketAddress? inet = id as GLib.InetSocketAddress;
        if (inet != null) {
            return inet.address.to_string();
        }

        return id.to_string();
    }


    public GLib.TlsDatabase parent { get; private set; }

    private GLib.File store_dir;
    private Gee.Map<string,TrustContext> pinned_certs =
        new Gee.HashMap<string,TrustContext>();


    public TlsDatabase(GLib.TlsDatabase parent, GLib.File store_dir) {
        this.parent = parent;
        this.store_dir = store_dir;
    }

    public void pin_certificate(GLib.TlsCertificate certificate,
                                GLib.SocketConnectable identity,
                                GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        string id = to_name(identity);
        TrustContext context = new TrustContext(certificate);
        lock (this.pinned_certs) {
            this.pinned_certs.set(id, context);
        }
    }

    public override string?
        create_certificate_handle(GLib.TlsCertificate certificate) {
        TrustContext? context = lookup_tls_certificate(certificate);
        return (context != null)
            ? context.id
            : this.parent.create_certificate_handle(certificate);
    }

    public override GLib.TlsCertificate?
        lookup_certificate_for_handle(string handle,
                                      GLib.TlsInteraction? interaction,
                                      GLib.TlsDatabaseLookupFlags flags,
                                      GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        TrustContext? context = lookup_id(handle);
        return (context != null)
            ? context.certificate
            : this.parent.lookup_certificate_for_handle(
                handle, interaction, flags, cancellable
            );
    }

    public override async GLib.TlsCertificate
        lookup_certificate_for_handle_async(string handle,
                                            GLib.TlsInteraction? interaction,
                                            GLib.TlsDatabaseLookupFlags flags,
                                            GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        TrustContext? context = lookup_id(handle);
        return (context != null)
            ? context.certificate
            : yield this.parent.lookup_certificate_for_handle_async(
                handle, interaction, flags, cancellable
            );
    }

    public override GLib.TlsCertificate
        lookup_certificate_issuer(GLib.TlsCertificate certificate,
                                  GLib.TlsInteraction? interaction,
                                  GLib.TlsDatabaseLookupFlags flags,
                                  GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return this.parent.lookup_certificate_issuer(
            certificate, interaction, flags, cancellable
        );
    }

    public override async GLib.TlsCertificate
        lookup_certificate_issuer_async(GLib.TlsCertificate certificate,
                                        GLib.TlsInteraction? interaction,
                                        GLib.TlsDatabaseLookupFlags flags,
                                        GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return yield this.parent.lookup_certificate_issuer_async(
            certificate, interaction, flags, cancellable
        );
    }

    public override GLib.List<GLib.TlsCertificate>
        lookup_certificates_issued_by(ByteArray issuer_raw_dn,
                                      GLib.TlsInteraction? interaction,
                                      GLib.TlsDatabaseLookupFlags flags,
                                      GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return this.parent.lookup_certificates_issued_by(
            issuer_raw_dn, interaction, flags, cancellable
        );
    }

    public override async GLib.List<GLib.TlsCertificate>
        lookup_certificates_issued_by_async(GLib.ByteArray issuer_raw_dn,
                                            GLib.TlsInteraction? interaction,
                                            GLib.TlsDatabaseLookupFlags flags,
                                            GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return yield this.parent.lookup_certificates_issued_by_async(
            issuer_raw_dn, interaction, flags, cancellable
        );
    }

    public override GLib.TlsCertificateFlags
        verify_chain(GLib.TlsCertificate chain,
                     string purpose,
                     GLib.SocketConnectable? identity,
                     GLib.TlsInteraction? interaction,
                     GLib.TlsDatabaseVerifyFlags flags,
                     GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        GLib.TlsCertificateFlags ret = this.parent.verify_chain(
            chain, purpose, identity, interaction, flags, cancellable
        );
        if (should_verify(ret, purpose, identity) &&
            verify(chain, identity, cancellable)) {
            ret = 0;
        }
        return ret;
    }

    public override async GLib.TlsCertificateFlags
        verify_chain_async(GLib.TlsCertificate chain,
                           string purpose,
                           GLib.SocketConnectable? identity,
                           GLib.TlsInteraction? interaction,
                           GLib.TlsDatabaseVerifyFlags flags,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        GLib.TlsCertificateFlags ret = yield this.parent.verify_chain_async(
            chain, purpose, identity, interaction, flags, cancellable
        );
        if (should_verify(ret, purpose, identity) &&
            yield verify_async(chain, identity, cancellable)) {
            ret = 0;
        }
        return ret;
    }

    private inline bool should_verify(GLib.TlsCertificateFlags parent_ret,
                                      string purpose,
                                      GLib.SocketConnectable? identity) {
        // If the parent didn't verify, check for a locally pinned
        // cert if it looks like we should, but always reject revoked
        // certs
        return (
            parent_ret != 0 &&
            !(GLib.TlsCertificateFlags.REVOKED in parent_ret) &&
            purpose == GLib.TlsDatabase.PURPOSE_AUTHENTICATE_SERVER &&
            identity != null
        );
    }

    private bool verify(GLib.TlsCertificate chain,
                        GLib.SocketConnectable identity,
                        GLib.Cancellable? cancellable)
        throws GLib.Error {
        string id = to_name(identity);
        TrustContext? context = null;
        lock (this.pinned_certs) {
            context = this.pinned_certs.get(id);
        }
        return (context != null);
    }

    private async bool verify_async(GLib.TlsCertificate chain,
                                    GLib.SocketConnectable identity,
                                    GLib.Cancellable? cancellable)
        throws GLib.Error {
        bool is_valid = false;
        yield Geary.Nonblocking.Concurrent.global.schedule_async(() => {
                is_valid = verify(chain, identity, cancellable);
            }, cancellable);
        return is_valid;
    }

    private TrustContext? lookup_id(string id) {
        lock (this.pinned_certs) {
            return Geary.traverse(this.pinned_certs.values).first_matching(
                (ctx) => ctx.id == id
            );
        }
    }

    private TrustContext? lookup_tls_certificate(GLib.TlsCertificate cert) {
        lock (this.pinned_certs) {
            return Geary.traverse(this.pinned_certs.values).first_matching(
                (ctx) => ctx.certificate.is_same(cert)
            );
        }
    }

}
