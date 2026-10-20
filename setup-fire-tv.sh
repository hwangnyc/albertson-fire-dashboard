#!/usr/bin/env bash
#
# Albertson Fire TV - one-command kiosk setup for Raspberry Pi OS (Bookworm).
#
# What it does:
#   1. Installs Chromium (+ unclutter to hide the mouse cursor)
#   2. Sets the Pi to boot straight to the desktop, auto-logged in
#   3. Disables screen blanking / power saving
#   4. Auto-launches the fire dashboard fullscreen on every boot,
#      with a watchdog that relaunches Chromium if it ever exits
#   5. Adds a daily 4 AM reboot to keep things fresh
#
# Run this ON THE PI (one line):
#   curl -fsSL https://raw.githubusercontent.com/hwangnyc/albertson-fire-dashboard/main/setup-fire-tv.sh | sudo bash
#
# After the reboot: enter the department passphrase in the dashboard and
# check "Trust this device" so it stays logged in across reboots.
#
set -euo pipefail

DASH_URL="https://hwangnyc.github.io/albertson-fire-dashboard/?pi=firehouse-tv-1"

say(){ echo "[fire-tv] $*"; }

# --- find the desktop user (the human account that auto-logs in) ---
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  TARGET_USER="${SUDO_USER:-}"
  [ -n "$TARGET_USER" ] || { echo "Run it as:  curl -fsSL <url> | sudo bash   (from the desktop user's shell)"; exit 1; }
else
  TARGET_USER="$USER"
  sudo -n true 2>/dev/null || { echo "This script needs sudo. Run:  curl -fsSL <url> | sudo bash"; exit 1; }
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[ -n "$TARGET_HOME" ] && [ -d "$TARGET_HOME" ] || { echo "Cannot find home directory for $TARGET_USER"; exit 1; }
TARGET_GROUP="$(id -gn "$TARGET_USER")"
say "Desktop user: $TARGET_USER ($TARGET_HOME)"

if [ ! -f /proc/device-tree/model ]; then
  say "WARNING: this does not look like a Raspberry Pi - continuing anyway"
fi

# --- packages ---
say "Installing Chromium..."
sudo apt-get update -qq
if ! sudo apt-get install -y -qq chromium unclutter curl; then
  sudo apt-get install -y -qq chromium-browser unclutter curl
fi
CHROME="$(command -v chromium || command -v chromium-browser)"
say "Chromium: $CHROME"

# --- boot to desktop, auto-logged in ---
say "Setting boot-to-desktop with autologin..."
sudo raspi-config nonint do_boot_behaviour B4 2>/dev/null || true

# --- disable screen blanking (Bookworm/Wayland path; harmless if unsupported) ---
say "Disabling screen blanking..."
sudo raspi-config nonint do_blanking 0 2>/dev/null || true

# --- X11 fallback blanking guards (no-op on Wayland, effective on X11) ---
sudo mkdir -p /etc/xdg/lxsession/LXDE-pi
if ! sudo grep -q "xset s off" /etc/xdg/lxsession/LXDE-pi/autostart 2>/dev/null; then
  sudo tee -a /etc/xdg/lxsession/LXDE-pi/autostart >/dev/null <<'EOF'
@xset s off
@xset -dpms
@xset s noblank
EOF
fi

# --- kiosk launcher: waits for network, launches Chromium, relaunches on exit ---
say "Installing kiosk launcher (with watchdog)..."
sudo -u "$TARGET_USER" mkdir -p "$TARGET_HOME/.local/bin" "$TARGET_HOME/.config/autostart"
sudo tee "$TARGET_HOME/.local/bin/fire-tv-kiosk.sh" >/dev/null <<EOF
#!/usr/bin/env bash
# Fire TV kiosk launcher + watchdog: relaunches Chromium if it ever exits.
URL="$DASH_URL"
CHROME="$CHROME"
# Wait for network (up to ~2 min) so the first paint is not an offline page.
for i in \$(seq 1 24); do
  curl -fsI --max-time 5 https://hwangnyc.github.io >/dev/null 2>&1 && break
  sleep 5
done
# Hide the mouse cursor after 1s idle (X11 only; harmless elsewhere).
command -v unclutter >/dev/null 2>&1 && (unclutter -idle 1 -root >/dev/null 2>&1 &)
while true; do
  # Clear Chromium's crash flags so a power cut never shows "Restore pages?".
  rm -rf "\$HOME/.config/chromium/Singleton"*
  "\$CHROME" \
    --kiosk \
    --noerrdialogs \
    --disable-session-crashed-bubble \
    --disable-infobars \
    --disable-pinch \
    --overscroll-history-navigation=0 \
    --no-first-run \
    --password-store=basic \
    --disable-features=Translate \
    --check-for-update-interval=31536000 \
    --ozone-platform-hint=auto \
    "\$URL"
  echo "[fire-tv] Chromium exited; relaunching in 5s"
  sleep 5
done
EOF
sudo chmod +x "$TARGET_HOME/.local/bin/fire-tv-kiosk.sh"
sudo chown "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.local/bin/fire-tv-kiosk.sh"

# --- autostart on desktop login (honored by labwc/Wayland and LXDE/X11) ---
sudo tee "$TARGET_HOME/.config/autostart/fire-tv.desktop" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=Fire TV Dashboard
Exec=$TARGET_HOME/.local/bin/fire-tv-kiosk.sh
X-GNOME-Autostart-enabled=true
EOF
sudo chown "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.config/autostart/fire-tv.desktop"

# --- daily 4 AM reboot ---
if ! sudo crontab -l 2>/dev/null | grep -q "fire-tv daily reboot"; then
  say "Adding daily 4 AM reboot..."
  (sudo crontab -l 2>/dev/null; echo "0 4 * * * /sbin/reboot # fire-tv daily reboot") | sudo crontab -
fi

say ""
say "Done. Rebooting in 15 seconds - press Ctrl+C to cancel."
say "After reboot: enter the department passphrase and check 'Trust this device'."
sleep 15
sudo reboot
