/* Copyright 2014-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
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
            document_font_changed();
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
            monospace_font_changed();
        }
    }
    
    private string _interface_font;
    public string interface_font {
        get {
            return _interface_font;
        }
        set {
            _interface_font = value;
            interface_font_changed();
        }
    }
    
    public signal void document_font_changed();
    public signal void monospace_font_changed();
    public signal void interface_font_changed();
    
    public StylishWebView() {
        Settings system_settings = GearyApplication.instance.config.gnome_interface;
        system_settings.bind("document-font-name", this, "document-font", SettingsBindFlags.DEFAULT);
        system_settings.bind("monospace-font-name", this, "monospace-font", SettingsBindFlags.DEFAULT);
        system_settings.bind("font-name", this, "interface-font", SettingsBindFlags.DEFAULT);
    }
}

