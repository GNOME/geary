#!/bin/sh
#
# Wrapper script to use for the Meson test setup.
#
# Define the "UI_TEST" for all tests that should run headless

xvfb-run 2>&1|grep --quiet auto-display
HAS_AUTO_DISPLAY="$?"
if [ "$HAS_AUTO_DISPLAY" -eq 0 ]; then
  OPT="-d"
else
  OPT="--auto-servernum"
fi
xvfb-run $OPT --server-args="-screen 0 1280x1024x24" \
  dbus-run-session -- "$@"

