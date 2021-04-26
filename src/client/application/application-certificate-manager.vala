/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// All of the code below basically exists since cert pinning using GCR
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


    // PCKS11 flag value lifted from pkcs11.h
    private const ulong CKF_WRITE_PROTECTED = 1UL << 1;


    private static async bool is_gcr_enabled(GLib.Cancellable? cancellable) {
        // Use GCR if it looks like it should be able to be
        // used. Specifically, if we can initialise the trust store
        // must have both lookup and store PKCS11 slot URIs or else it
        // won't be able to lookup or store pinned certs, secondly,
        // there must be at least a read-write store slot available.
        bool init_okay = false;
        try {
            init_okay = yield Gcr.pkcs11_initialize_async(cancellable);
        } catch (GLib.Error err) {
            warning("Failed to initialise GCR PCKS#11 modules: %s", err.message);
        }

        bool has_uris = false;
        if (init_okay) {
            has_uris = (
                !Geary.String.is_empty(Gcr.pkcs11_get_trust_store_uri()) &&
                Gcr.pkcs11_get_trust_lookup_uris().length > 0
            );
            if (has_uris) {
                debug("GCR slot URIs found: %s", has_uris.to_string());
            } else {
                warning(
                    "No GCR slot URIs found, GCR certificate pinning unavailable"
                );
            }
        }

        bool has_rw_store = false;
        if (has_uris) {
            Gck.Slot? store = Gcr.pkcs11_get_trust_store_slot();
            if (store != null) {
                has_rw_store = !store.has_flags(CKF_WRITE_PROTECTED);
                debug("GCR store is R/W: %s", has_rw_store.to_string());
            } else {
                warning("No GCR store found, GCR certificate pinning unavailable");
            }

            if (!has_rw_store) {
                warning("GCR store is not RW, GCR certificate pinning unavailable");
            }
        }

        return has_rw_store;
    }


    private TlsDatabase? pinning_database;


    /**
     * Constructs a new instance, globally installing the pinning database.
     */
    public async CertificateManager(GLib.File store_dir,
                                    GLib.Cancellable? cancellable) {
        bool use_gcr = yield is_gcr_enabled(cancellable);
        this.pinning_database = new TlsDatabase(
            GLib.TlsBackend.get_default().get_default_database(),
            store_dir,
            use_gcr
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
            yield this.pinning_database.pin_certificate(
                endpoint.untrusted_certificate,
                endpoint.remote,
                save,
                cancellable
            );
        } catch (GLib.Error err) {
            throw new CertificateManagerError.STORE_FAILED(err.message);
        }
    }

}


/**
 * TLS database that observes locally pinned certs.
 *
 * An instance of this is managed by {@link CertificateManager}, the
 * application should simply construct an instance of that.
 */
internal class Application.TlsDatabase : GLib.TlsDatabase {


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

        public TrustContext.lookup(GLib.File dir,
                                   string identity,
                                   GLib.Cancellable? cancellable)
            throws GLib.Error {
            // This isn't async so that we can support both
            // verify_chain and verify_chain_async with the same call
            GLib.File storage = dir.get_child(FILENAME_FORMAT.printf(identity));
            GLib.FileInputStream f_in = storage.read(cancellable);
            GLib.BufferedInputStream buf = new GLib.BufferedInputStream(f_in);
            GLib.ByteArray cert_pem = new GLib.ByteArray.sized(buf.buffer_size);
            bool eof = false;
            while (!eof) {
                size_t filled = buf.fill(-1, cancellable);
                if (filled > 0) {
                    cert_pem.append(buf.peek_buffer());
                    buf.skip(filled, cancellable);
                } else {
                    eof = true;
                }
            }
            buf.close(cancellable);

            this(new GLib.TlsCertificate.from_pem((string) cert_pem.data, -1));
        }

        public async void save(GLib.File dir,
                               string identity,
                               GLib.Cancellable? cancellable)
            throws GLib.Error {
            yield Geary.Files.make_directory_with_parents(dir, cancellable);
            GLib.File storage = dir.get_child(FILENAME_FORMAT.printf(identity));
            GLib.FileOutputStream f_out = yield storage.replace_async(
                null, false, GLib.FileCreateFlags.NONE, IO_PRIO, cancellable
            );
            GLib.BufferedOutputStream buf = new GLib.BufferedOutputStream(f_out);

            size_t written = 0;
            yield buf.write_all_async(
                this.certificate.certificate_pem.data,
                IO_PRIO,
                cancellable,
                out written
            );
            yield buf.close_async(IO_PRIO, cancellable);
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


    private GLib.TlsDatabase parent { get; private set; }
    private GLib.File store_dir;
    private bool use_gcr;

    private Gee.Map<string,TrustContext> pinned_certs =
        new Gee.HashMap<string,TrustContext>();


        public TlsDatabase(GLib.TlsDatabase parent,
                           GLib.File store_dir,
                           bool use_gcr) {
        this.parent = parent;
        this.store_dir = store_dir;
        this.use_gcr = use_gcr;
    }

    public async void pin_certificate(GLib.TlsCertificate certificate,
                                      GLib.SocketConnectable identity,
                                      bool save,
                                      GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        string id = to_name(identity);
        TrustContext context = new TrustContext(certificate);
        lock (this.pinned_certs) {
            this.pinned_certs.set(id, context);
        }
        if (save) {
            if (this.use_gcr) {
                yield Gcr.trust_add_pinned_certificate_async(
                    new Gcr.SimpleCertificate(certificate.certificate.data),
                    GLib.TlsDatabase.PURPOSE_AUTHENTICATE_SERVER,
                    id,
                    cancellable
                );
            } else {
                yield context.save(
                    this.store_dir, to_name(identity), cancellable
                );
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
        if (check_pinned(ret, purpose, identity) &&
            is_pinned(chain, identity, cancellable)) {
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
        if (check_pinned(ret, purpose, identity) &&
            yield is_pinned_async(chain, identity, cancellable)) {
            ret = 0;
        }
        return ret;
    }

    private inline bool check_pinned(GLib.TlsCertificateFlags parent_ret,
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

    private bool is_pinned(GLib.TlsCertificate chain,
                           GLib.SocketConnectable identity,
                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        bool is_pinned = false;
        string id = to_name(identity);
        TrustContext? context = null;
        lock (this.pinned_certs) {
            context = this.pinned_certs.get(id);
            if (context != null) {
                is_pinned = context.certificate.is_same(chain);
            } else {
                // Cert not found in memory, check with GCR if
                // enabled.
                if (this.use_gcr) {
                    is_pinned = Gcr.trust_is_certificate_pinned(
                        new Gcr.SimpleCertificate(chain.certificate.data),
                        GLib.TlsDatabase.PURPOSE_AUTHENTICATE_SERVER,
                        id,
                        cancellable
                    );
                }

                if (!is_pinned) {
                    // Cert is not pinned in memory or in GCR, so look
                    // for it on disk. Do this even if GCR support is
                    // enabled, since if the cert was previously saved
                    // to disk, it should still be able to be used
                    try {
                        context = new TrustContext.lookup(
                            this.store_dir, id, cancellable
                        );
                        this.pinned_certs.set(id, context);
                        is_pinned = context.certificate.is_same(chain);
                    } catch (GLib.IOError.NOT_FOUND err) {
                        // Cert was not found saved, so it not pinned
                    } catch (GLib.Error err) {
                        Geary.ErrorContext err_context =
                            new Geary.ErrorContext(err);
                        debug("Error loading pinned certificate: %s",
                              err_context.format_full_error());
                    }
                }
            }
        }
        return is_pinned;
    }

    private async bool is_pinned_async(GLib.TlsCertificate chain,
                                       GLib.SocketConnectable identity,
                                       GLib.Cancellable? cancellable)
        throws GLib.Error {
        bool pinned = false;
        yield Geary.Nonblocking.Concurrent.global.schedule_async(() => {
                pinned = is_pinned(chain, identity, cancellable);
            }, cancellable);
        return pinned;
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
