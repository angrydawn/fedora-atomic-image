# Start the graphical session only for the local tty1 login. Terminal windows,
# SSH sessions, containers, and the other virtual consoles are unaffected.
if [ "$(tty 2>/dev/null)" = /dev/tty1 ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    exec /usr/bin/dbus-run-session /usr/bin/startlxqtwayland
fi
