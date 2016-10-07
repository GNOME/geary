/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class StylishWebView : WebKit.WebView {

    private string _document_font;
    public string document_font {
        get {
            return _document_font;
        }
        set {
            _document_font = value;
            Pango.FontDescription font = Pango.FontDescription.from_string(value);
            WebKit.WebSettings config = settings;
            config.default_font_family = font.get_family();
            config.default_font_size = font.get_size() / Pango.SCALE;
            settings = config;
        }
    }

    private string _monospace_font;
    public string monospace_font {
        get {
            return _monospace_font;
        }
        set {
            _monospace_font = value;
            Pango.FontDescription font = Pango.FontDescription.from_string(value);
            WebKit.WebSettings config = settings;
            config.monospace_font_family = font.get_family();
            config.default_monospace_font_size = font.get_size() / Pango.SCALE;
            settings = config;
        }
    }

    public StylishWebView() {
        Settings system_settings = GearyApplication.instance.config.gnome_interface;
        system_settings.bind("document-font-name", this, "document-font", SettingsBindFlags.DEFAULT);
        system_settings.bind("monospace-font-name", this, "monospace-font", SettingsBindFlags.DEFAULT);
    }
}

