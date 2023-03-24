#!/bin/bash

cat > org.gnome.Geary.gresource.xml << EOF
<?xml version='1.0' encoding='UTF-8'?>
<gresources>
  <gresource prefix="/org/gnome/Geary">
EOF

for ui in gtk/*.ui
do
    basename=$(basename $ui)
    echo "    <file compressed=\"true\" preprocess=\"xml-stripblanks\" alias=\"$basename\">$ui</file>"
done >> org.gnome.Geary.gresource.xml

for css in css/*.css
do
    basename=$(basename $css)
    echo "    <file compressed=\"true\" alias=\"$basename\">$css</file>"
done >> org.gnome.Geary.gresource.xml

for web in web/*.html web/*.js
do
    basename=$(basename $web)
    echo "    <file compressed=\"true\" alias=\"$basename\">$web</file>"
done >> org.gnome.Geary.gresource.xml


cat >> org.gnome.Geary.gresource.xml << EOF
  </gresource>
</gresources>
EOF



