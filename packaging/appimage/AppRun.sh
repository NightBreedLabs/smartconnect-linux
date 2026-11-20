#!/bin/sh
# Entry point of the Smart Connect AppImage (sharun runs it as the AppRun).
#
#   SmartConnect.AppImage                 opens the GTK app
#   SmartConnect.AppImage <program> ARGS  runs one of the bundled programs, e.g. smartconnectd
#   SmartConnect.AppImage --install [--enable]
#                                         unpacks itself to ~/.local/opt/smartconnect-linux, links
#                                         the programs into ~/.local/bin and adds the launcher, the
#                                         systemd user unit and (when Noctalia is there) the plugin;
#                                         --enable also starts the daemon now and at every login
#   SmartConnect.AppImage --uninstall     removes all of that again (settings and pairing are kept)
#
# Installing matters: the daemon runs in the background for as long as you are logged in, and an
# AppImage's files only exist while the AppImage that started them runs. The unpacked copy also has
# a fixed path, which KDE Plasma needs to trust the display helper.

if [ "$APPRUN_DEBUG" = 1 ]; then
	set -x
fi
set -e

MAIN_BIN=smartconnect-gui
PROGRAMS="smartconnectd smartconnect-gui smartconnect-mirror smartconnect-crosscontrol smartconnect-display smartconnect-webcam smartconnect-files smartconnect-fex"
APP_ID=dev.smartconnect.Linux
ARG0="${ARGV0:-$0}"
unset ARGV0

export PATH="$APPDIR/bin:$PATH"
export ARG0 APPDIR PATH

data_home=${XDG_DATA_HOME:-$HOME/.local/share}
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
opt_dir=$HOME/.local/opt/smartconnect-linux
bin_dir=$HOME/.local/bin
apps_dir=$data_home/applications
icon_dir=$data_home/icons/hicolor/scalable/apps
unit_dir=$config_home/systemd/user
plugin_dir=$config_home/noctalia/plugins/smart-connect

say() { printf '==> %s\n' "$*"; }

have_user_manager() {
	command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1
}

install_app() {
	enable=0
	for a do
		case "$a" in
			--install) ;;
			--enable) enable=1 ;;
			*) echo "unknown option: $a" >&2; exit 2 ;;
		esac
	done

	say "Unpacking to $opt_dir"
	mkdir -p "${opt_dir%/*}"
	rm -rf "$opt_dir.new"
	cp -a "$APPDIR"/. "$opt_dir.new"/
	# A running daemon keeps its files open: move the old copy aside before deleting it.
	if [ -d "$opt_dir" ]; then
		rm -rf "$opt_dir.old"
		mv "$opt_dir" "$opt_dir.old"
	fi
	mv "$opt_dir.new" "$opt_dir"
	rm -rf "$opt_dir.old"

	say "Linking the programs into $bin_dir"
	mkdir -p "$bin_dir"
	for p in $PROGRAMS; do
		ln -sfn "$opt_dir/bin/$p" "$bin_dir/$p"
	done
	case ":$PATH:" in
		*":$bin_dir:"*) ;;
		*) echo "    note: $bin_dir is not on your PATH; the launcher and the systemd unit don't need it" ;;
	esac

	say "Adding the launcher, the icon and the display helper's KDE entry"
	share=$opt_dir/share/smartconnect-linux
	mkdir -p "$apps_dir" "$icon_dir"
	# Absolute Exec= lines: they work without PATH, and KWin matches the display helper's
	# entry against the real path of the running program.
	sed -e "s|^Exec=smartconnect-gui|Exec=$opt_dir/bin/smartconnect-gui|" \
		"$share/$APP_ID.desktop" > "$apps_dir/$APP_ID.desktop"
	sed -e "s|^Exec=smartconnect-display|Exec=$opt_dir/bin/smartconnect-display|" \
		"$share/dev.smartconnect.Display.desktop" > "$apps_dir/dev.smartconnect.Display.desktop"
	cp -f "$share/$APP_ID.svg" "$icon_dir/$APP_ID.svg"
	command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$apps_dir" || :
	command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1 || :
	command -v kbuildsycoca5 >/dev/null 2>&1 && kbuildsycoca5 >/dev/null 2>&1 || :
	command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t -f "$data_home/icons/hicolor" 2>/dev/null || :

	say "Installing the systemd user unit"
	mkdir -p "$unit_dir"
	sed -e "s|%h/\.local/bin/smartconnectd|$opt_dir/bin/smartconnectd|g" \
		"$share/smartconnectd.service" > "$unit_dir/smartconnectd.service"

	if [ -d "$config_home/noctalia" ]; then
		say "Installing the Noctalia plugin to $plugin_dir (your plugin settings are kept)"
		mkdir -p "$plugin_dir"
		if [ -f "$plugin_dir/settings.json" ]; then
			cp -f "$plugin_dir/settings.json" "$opt_dir/noctalia-settings.json.keep"
		fi
		rm -rf "$plugin_dir"
		cp -a "$share/noctalia-plugin" "$plugin_dir"
		if [ -f "$opt_dir/noctalia-settings.json.keep" ]; then
			mv -f "$opt_dir/noctalia-settings.json.keep" "$plugin_dir/settings.json"
		fi
	fi

	if have_user_manager; then
		systemctl --user daemon-reload
		if [ "$enable" = 1 ]; then
			say "Enabling and (re)starting smartconnectd"
			systemctl --user enable smartconnectd.service
			systemctl --user restart smartconnectd.service
		elif systemctl --user is-active --quiet smartconnectd.service; then
			say "Restarting the running smartconnectd on the new version"
			systemctl --user restart smartconnectd.service
		fi
	else
		autostart_dir=$config_home/autostart
		if [ "$enable" = 1 ]; then
			say "Installing XDG autostart entry (non-systemd user session)"
			mkdir -p "$autostart_dir"
			cat <<-AUTOF > "$autostart_dir/smartconnectd.desktop"
			[Desktop Entry]
			Type=Application
			Name=Smart Connect Daemon
			Exec=$opt_dir/bin/smartconnectd
			Terminal=false
			NoDisplay=true
			X-GNOME-Autostart-enabled=true
			AUTOF
		fi
	fi

	cat <<-EOF

	Done. Open "Smart Connect" from your app launcher (or run $opt_dir/bin/smartconnect-gui).
	The app starts the daemon when it opens. To run it at every login without the app:
	    systemctl --user enable --now smartconnectd
	Things the AppImage can't do for you (they need root): the firewall rules, and the optional
	v4l2loopback (webcam) and vkms (Extend on niri) kernel modules. See docs/installation.md.
	You can delete the AppImage file now; run it again with --install to update.
	EOF
}

uninstall_app() {
	if have_user_manager; then
		systemctl --user disable --now smartconnectd.service 2>/dev/null || :
	fi
	rm -f "$unit_dir/smartconnectd.service" "$config_home/autostart/smartconnectd.desktop"
	have_user_manager && systemctl --user daemon-reload || :
	for p in $PROGRAMS; do
		# Only our own links: never a program installed another way under the same name.
		if [ -L "$bin_dir/$p" ] && [ "$(readlink "$bin_dir/$p")" = "$opt_dir/bin/$p" ]; then
			rm -f "$bin_dir/$p"
		fi
	done
	rm -f "$apps_dir/$APP_ID.desktop" "$apps_dir/dev.smartconnect.Display.desktop" "$icon_dir/$APP_ID.svg"
	rm -rf "$opt_dir"
	echo "Removed. Your settings and pairing (~/.config/smartconnect-linux, ~/.local/share/smartconnect-linux)"
	echo "and the Noctalia plugin ($plugin_dir) are left in place."
}

doctor_check() {
	echo "Smart Connect for Linux — Preflight & Diagnostic Check"
	echo "======================================================"
	echo ""
	echo "Desktop & Compositor:"
	echo "  XDG_CURRENT_DESKTOP: ${XDG_CURRENT_DESKTOP:-unknown}"
	echo "  WAYLAND_DISPLAY:     ${WAYLAND_DISPLAY:-none (X11?)}"
	echo ""
	echo "System Services & Tools:"
	for cmd in avahi-daemon bluetoothctl systemctl wl-copy fusermount3; do
		if command -v "$cmd" >/dev/null 2>&1; then
			printf "  [ok] %-16s found\n" "$cmd"
		else
			printf "  [!]  %-16s MISSING\n" "$cmd"
		fi
	done
	echo ""
	echo "Hardware Video Acceleration (VA-API):"
	if command -v vainfo >/dev/null 2>&1; then
		vainfo 2>&1 | head -n 8 | sed 's/^/  /'
	else
		echo "  vainfo not found (install libva-utils to inspect VA-API drivers)"
	fi
	echo ""
	echo "Kernel Modules:"
	for mod in v4l2loopback vkms; do
		if lsmod 2>/dev/null | grep -q "^$mod"; then
			printf "  [ok] %-16s loaded\n" "$mod"
		else
			printf "  [-]  %-16s not loaded (optional: %s)\n" "$mod" "$([ "$mod" = "v4l2loopback" ] && echo "phone as webcam" || echo "Extend display on niri")"
		fi
	done
	echo ""
}

case "$1" in
	--doctor|doctor) doctor_check; exit 0 ;;
	--install) install_app "$@"; exit 0 ;;
	--uninstall) uninstall_app; exit 0 ;;
	--appimage-add-env)
		# Per-AppImage environment variables (uruntime).
		shift
		for v do
			echo "$v" >> "$APPIMAGE".env
			>&2 echo "Added '$v' to $APPIMAGE.env"
		done
		exit 0 ;;
esac

if [ -f "$APPDIR"/AppRun.lib ]; then
	. "$APPDIR"/AppRun.lib
	for hook in "$APPDIR"/bin/*.hook; do
		[ -e "$hook" ] || continue
		. "$hook"
	done
fi

# A program by link name (a symlink to the AppImage called smartconnectd), by first argument,
# else the GTK app.
if [ -f "$APPDIR"/bin/"${ARG0##*/}" ]; then
	TO_LAUNCH=$APPDIR/bin/${ARG0##*/}
elif [ -n "$1" ] && [ -f "$APPDIR"/bin/"$1" ]; then
	TO_LAUNCH=$APPDIR/bin/$1
	shift
else
	TO_LAUNCH=$APPDIR/bin/$MAIN_BIN
fi
exec "$TO_LAUNCH" "$@"
