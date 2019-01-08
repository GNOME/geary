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


    private class TrustContext {

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

        public string id;
        public Gcr.Certificate certificate;
        public Gee.Set<string> pinned_identities = new Gee.HashSet<string>();


        public TrustContext(Gcr.Certificate certificate) {
            this.id = certificate.get_fingerprint_hex(GLib.ChecksumType.SHA256);
            this.certificate = certificate;
        }

        public bool add_identity(GLib.SocketConnectable id) {
            return this.pinned_identities.add(to_name(id));
        }

        public bool matches_identity(GLib.SocketConnectable id) {
            return this.pinned_identities.contains(to_name(id));
        }

        public GLib.TlsCertificate to_tls_certificate()
            throws GLib.Error {
            //return new GLib.TlsCertificate.from_pem(
            //    this.certificate.get_pem_data(), -1
            //);
            warning("Was actually asked to make a TLS cert from a GCR cert");
            throw new GLib.IOError.NOT_SUPPORTED("TODO");
        }

    }


    public GLib.TlsDatabase parent { get; private set; }

    private Gee.List<TrustContext> contexts =
        new Gee.ArrayList<TrustContext>();


    public TlsDatabase(GLib.TlsDatabase parent) {
        this.parent = parent;
    }


    public void pin_certificate(GLib.TlsCertificate certificate,
                                GLib.SocketConnectable identity) {
        Gcr.Certificate gcr = new Gcr.SimpleCertificate(
            certificate.certificate.data
        );
        lock (this.contexts) {
            TrustContext? context = lookup_gcr_unlocked(gcr);
            if (context == null) {
                context = new TrustContext(gcr);
                debug("Adding certificate %s",
                      gcr.get_fingerprint_hex(GLib.ChecksumType.SHA1));
                this.contexts.add(context);
            }
            if (context.add_identity(identity)){
                debug("Adding identity %s", identity.to_string());
            }
        }
    }

    public void remove_certificate(Gcr.Certificate certificate) {
        lock (this.contexts) {
            TrustContext? context = lookup_gcr_unlocked(certificate);
            if (context != null) {
                this.contexts.remove(context);
            }
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
            ? context.to_tls_certificate()
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
            ? context.to_tls_certificate()
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
        debug("Verifying cert sync: %s: %s",
              purpose,
              identity != null ? identity.to_string() : "[no identity]");
        GLib.TlsCertificateFlags ret = this.parent.verify_chain(
            chain, purpose, identity, interaction, flags, cancellable
        );
        if (should_verify(ret, purpose, identity)) {
            debug("Looking for pinned cert");
            TrustContext? context = lookup_tls_certificate(chain);
            if (context != null) {
                debug("Have trust context with %d ids", context.pinned_identities.size);
            }
            if (context != null && context.matches_identity(identity)) {
                ret = 0;
            }
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
        debug("Verifying cert async: %s: %s",
              purpose,
              identity != null ? identity.to_string() : "[no identity]");
        GLib.TlsCertificateFlags ret = yield this.parent.verify_chain_async(
            chain, purpose, identity, interaction, flags, cancellable
        );
        if (should_verify(ret, purpose, identity)) {
            debug("Looking for pinned cert");
            TrustContext? context = lookup_tls_certificate(chain);
            if (context != null) {
                debug("Have trust context with %d ids", context.pinned_identities.size);
            }
            if (context != null && context.matches_identity(identity)) {
                ret = 0;
            }
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

    private TrustContext? lookup_id(string id) {
        lock (this.contexts) {
            return Geary.traverse(this.contexts).first_matching(
                (ctx) => ctx.id == id
            );
        }
    }

    private TrustContext? lookup_tls_certificate(GLib.TlsCertificate tls) {
        lock (this.contexts) {
            return lookup_gcr_unlocked(
                new Gcr.SimpleCertificate(tls.certificate.data)
            );
        }
    }

    private TrustContext? lookup_gcr_unlocked(Gcr.Certificate cert) {
        debug("Looking for %s", cert.get_fingerprint_hex(GLib.ChecksumType.SHA1));
        return Geary.traverse(this.contexts).first_matching(
            (ctx) => Gcr.Certificate.compare(ctx.certificate, cert) == 0
        );
    }

}
