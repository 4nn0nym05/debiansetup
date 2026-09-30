#!/usr/bin/env bash
# ============================================================
# Debian minimal -> dwm/st/dmenu/slstatus desktop
#   - Xorg + xinit, greetd + tuigreet login -> startx
#   - sudo installed, user added to sudo group
#   - NetworkManager (nmtui) + wifi firmware, network status in bar
#   - zram swap (zstd, 50% RAM)
#   - quiet boot (hidden GRUB, loglevel=3, boot output on tty2)
#   - dwm 6.8 + fullgaps, st 0.9.2, dmenu 5.4, slstatus 1.1
#   - Tokyo Night theme, JetBrainsMono Nerd Font, stock keybinds
#   - volume keys (amixer), battery/volume/time in bar
#   - Hyper-V modesetting fix (auto-detected, skipped on real HW)
#
# Usage (as root):  ./setup-suckless.sh <username>
# ============================================================
set -euo pipefail

TARGET_USER="${1:-}"
if [[ -z "$TARGET_USER" ]]; then
    echo "Usage: $0 <username>"; exit 1
fi
if [[ $EUID -ne 0 ]]; then
    echo "Run as root."; exit 1
fi
if ! id "$TARGET_USER" &>/dev/null; then
    echo "User '$TARGET_USER' does not exist."; exit 1
fi
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

SRC=/usr/local/src
DWM_VER=6.8
ST_VER=0.9.2
DMENU_VER=5.4
SLSTATUS_VER=1.1
SLOCK_VER=1.7

fetch_src() {  # fetch_src <url> <name> <ver>
    cd "$SRC"
    rm -rf "$SRC/$2-$3" "$SRC/$2"
    wget -q "$1"
    tar xzf "$2-$3.tar.gz"
    rm -f "$2-$3.tar.gz"
    mv "$2-$3" "$2"
    cd "$2"
}

# ------------------------------------------------------------
echo "==> Installing packages"
apt update
apt install -y \
    xserver-xorg xserver-xorg-video-all xinit x11-xserver-utils \
    build-essential libx11-dev libxft-dev libxinerama-dev libfreetype6-dev \
    libxrandr-dev libxext-dev libimlib2-dev \
    fontconfig git wget unzip python3 \
    alsa-utils sudo network-manager zram-tools

echo "==> Adding $TARGET_USER to sudo + netdev groups"
usermod -aG sudo,netdev "$TARGET_USER"

# GPU (Intel/AMD) + wifi firmware (Intel/Realtek/Atheros) — needs non-free-firmware in sources
apt install -y firmware-misc-nonfree firmware-amd-graphics firmware-iwlwifi firmware-realtek firmware-atheros \
    || echo "    WARN: firmware not available (non-free-firmware repo not enabled?)"

# NetworkManager ignores anything in /etc/network/interfaces, so strip it
# to loopback only (backup kept). Current connection keeps working until reboot.
echo "==> Handing network interfaces over to NetworkManager"
if grep -qvE '^\s*(#|$|source|auto lo|iface lo)' /etc/network/interfaces 2>/dev/null; then
    cp /etc/network/interfaces /etc/network/interfaces.bak
    cat > /etc/network/interfaces << 'EOF'
source /etc/network/interfaces.d/*
auto lo
iface lo inet loopback
EOF
    echo "    old config saved to /etc/network/interfaces.bak"
fi
systemctl enable NetworkManager

# bar helper: prints "wifi <SSID>", "eth", or "offline"
cat > /usr/local/bin/bar-net << 'EOF'
#!/bin/sh
nmcli -t -f TYPE,STATE,CONNECTION device 2>/dev/null | awk -F: '
  $2=="connected" && $1=="wifi"     { print "wifi " $3; f=1; exit }
  $2=="connected" && $1=="ethernet" { print "eth"; f=1; exit }
  END { if (!f) print "offline" }'
EOF
chmod +x /usr/local/bin/bar-net

# ------------------------------------------------------------
echo "==> Configuring zram swap (zstd, 50% of RAM)"
cat > /etc/default/zramswap << 'EOF'
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF
cat > /etc/sysctl.d/99-zram.conf << 'EOF'
vm.swappiness=100
vm.page-cluster=0
EOF
sysctl -q --system
systemctl enable zramswap
systemctl restart zramswap

# ------------------------------------------------------------
echo "==> Installing JetBrainsMono Nerd Font (system-wide)"
mkdir -p /usr/share/fonts/JetBrainsMonoNerd
wget -q https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -O /tmp/jbm.zip
unzip -oq /tmp/jbm.zip -d /usr/share/fonts/JetBrainsMonoNerd
rm -f /tmp/jbm.zip
fc-cache -f >/dev/null

mkdir -p "$SRC"

# ------------------------------------------------------------
echo "==> Writing keybind cheatsheet (Alt+F1)"
mkdir -p /usr/local/share
cat > /usr/local/share/dwm-keys.txt << 'EOF'
Alt+F1                  this cheatsheet (type to filter)
Alt+P                   dmenu (launcher)
Alt+Shift+Enter         terminal (st)
Alt+Shift+C             close window
Alt+Shift+Q             restart dwm
Alt+Shift+L             lock screen
Alt+Shift+E             log out (back to greeter)
Alt+J / Alt+K           focus next / prev window
Alt+Enter               swap focused window into master
Alt+H / Alt+L           shrink / grow master area
Alt+I / Alt+D           more / fewer master windows
Alt+Tab                 previous tag
Alt+T                   layout: tiled
Alt+F                   layout: floating
Alt+M                   layout: monocle
Alt+Space               toggle last layout
Alt+Shift+Space         toggle floating for window
Alt+B                   toggle bar
Alt+1..9                view tag
Alt+Shift+1..9          move window to tag
Alt+Ctrl+1..9           add/remove tag from view
Alt+Ctrl+Shift+1..9     add/remove window to/from tag
Alt+0                   view all tags
Alt+Shift+0             window on all tags
Alt+, / Alt+.           focus prev / next monitor
Alt+Shift+, / .         move window to prev / next monitor
Alt+LMB drag            move window
Alt+RMB drag            resize window
Alt+MMB                 toggle floating
Vol+ / Vol- / Mute      volume
st: Ctrl+Shift+C / V    copy / paste
st: Shift+Insert        paste primary selection
st: Ctrl+Shift+PgUp/Dn  font size + / -
st: Ctrl+Shift+Home     reset font size
nmtui (in st)           connect to wifi
EOF

# ------------------------------------------------------------
echo "==> Building dwm $DWM_VER"
fetch_src "https://dl.suckless.org/dwm/dwm-$DWM_VER.tar.gz" dwm "$DWM_VER"

wget -q https://dwm.suckless.org/patches/fullgaps/dwm-fullgaps-6.4.diff
patch -p1 < dwm-fullgaps-6.4.diff
rm -f dwm-fullgaps-6.4.diff

cat > config.h << 'DWMCONFIG'
/* See LICENSE file for copyright and license details. */
#include <X11/XF86keysym.h>

/* appearance */
static const unsigned int borderpx  = 2;
static const unsigned int snap      = 32;
static const unsigned int refreshrate = 60;
static const unsigned int gappx     = 10;
static const int showbar            = 1;
static const int topbar             = 1;
static const char *fonts[]          = { "JetBrainsMono Nerd Font:size=11" };
static const char dmenufont[]       = "JetBrainsMono Nerd Font:size=11";

/* Tokyo Night */
static const char col_bg_alt[]      = "#16161e";
static const char col_fg[]          = "#c0caf5";
static const char col_fg_dim[]      = "#565f89";
static const char col_accent[]      = "#7aa2f7";
static const char col_border[]      = "#292e42";

static const char *colors[][3]      = {
	/*               fg           bg           border   */
	[SchemeNorm] = { col_fg_dim,  col_bg_alt,  col_border },
	[SchemeSel]  = { col_fg,      col_bg_alt,  col_accent },
};

/* tagging */
static const char *tags[] = { "1", "2", "3", "4", "5", "6", "7", "8", "9" };

static const Rule rules[] = {
	/* class      instance    title       tags mask     isfloating   monitor */
	{ "Gimp",     NULL,       NULL,       0,            1,           -1 },
	{ "Firefox",  NULL,       NULL,       1 << 8,       0,           -1 },
};

/* layout(s) */
static const float mfact     = 0.55;
static const int nmaster     = 1;
static const int resizehints = 1;
static const int lockfullscreen = 1;

static const Layout layouts[] = {
	{ "[]=",      tile },
	{ "><>",      NULL },
	{ "[M]",      monocle },
};

/* key definitions — stock */
#define MODKEY Mod1Mask
#define TAGKEYS(KEY,TAG) \
	{ MODKEY,                       KEY,      view,           {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask,           KEY,      toggleview,     {.ui = 1 << TAG} }, \
	{ MODKEY|ShiftMask,             KEY,      tag,            {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask|ShiftMask, KEY,      toggletag,      {.ui = 1 << TAG} },

#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

static char dmenumon[2] = "0";
static const char *dmenucmd[] = { "dmenu_run", "-m", dmenumon, "-fn", dmenufont,
	"-nb", col_bg_alt, "-nf", col_fg_dim, "-sb", col_accent, "-sf", col_bg_alt, NULL };
static const char *termcmd[]  = { "st", NULL };

static const Key keys[] = {
	{ MODKEY,                       XK_p,      spawn,          {.v = dmenucmd } },
	{ MODKEY|ShiftMask,             XK_Return, spawn,          {.v = termcmd } },
	{ MODKEY,                       XK_b,      togglebar,      {0} },
	{ MODKEY,                       XK_j,      focusstack,     {.i = +1 } },
	{ MODKEY,                       XK_k,      focusstack,     {.i = -1 } },
	{ MODKEY,                       XK_i,      incnmaster,     {.i = +1 } },
	{ MODKEY,                       XK_d,      incnmaster,     {.i = -1 } },
	{ MODKEY,                       XK_h,      setmfact,       {.f = -0.05} },
	{ MODKEY,                       XK_l,      setmfact,       {.f = +0.05} },
	{ MODKEY,                       XK_Return, zoom,           {0} },
	{ MODKEY,                       XK_Tab,    view,           {0} },
	{ MODKEY|ShiftMask,             XK_c,      killclient,     {0} },
	{ MODKEY,                       XK_t,      setlayout,      {.v = &layouts[0]} },
	{ MODKEY,                       XK_f,      setlayout,      {.v = &layouts[1]} },
	{ MODKEY,                       XK_m,      setlayout,      {.v = &layouts[2]} },
	{ MODKEY,                       XK_space,  setlayout,      {0} },
	{ MODKEY|ShiftMask,             XK_space,  togglefloating, {0} },
	{ MODKEY,                       XK_0,      view,           {.ui = ~0 } },
	{ MODKEY|ShiftMask,             XK_0,      tag,            {.ui = ~0 } },
	{ MODKEY,                       XK_comma,  focusmon,       {.i = -1 } },
	{ MODKEY,                       XK_period, focusmon,       {.i = +1 } },
	{ MODKEY|ShiftMask,             XK_comma,  tagmon,         {.i = -1 } },
	{ MODKEY|ShiftMask,             XK_period, tagmon,         {.i = +1 } },
	TAGKEYS(                        XK_1,                      0)
	TAGKEYS(                        XK_2,                      1)
	TAGKEYS(                        XK_3,                      2)
	TAGKEYS(                        XK_4,                      3)
	TAGKEYS(                        XK_5,                      4)
	TAGKEYS(                        XK_6,                      5)
	TAGKEYS(                        XK_7,                      6)
	TAGKEYS(                        XK_8,                      7)
	TAGKEYS(                        XK_9,                      8)
	{ MODKEY|ShiftMask,             XK_q,      quit,           {0} },
	/* lock / logout */
	{ MODKEY|ShiftMask,             XK_l,      spawn,          SHCMD("slock") },
	{ MODKEY|ShiftMask,             XK_e,      spawn,          SHCMD("pkill -x Xorg") },
	/* keybind cheatsheet */
	{ MODKEY,                       XK_F1,     spawn,          SHCMD("dmenu -l 40 -p keys < /usr/local/share/dwm-keys.txt") },
	/* media keys */
	{ 0, XF86XK_AudioRaiseVolume, spawn, SHCMD("amixer set Master 5%+") },
	{ 0, XF86XK_AudioLowerVolume, spawn, SHCMD("amixer set Master 5%-") },
	{ 0, XF86XK_AudioMute,        spawn, SHCMD("amixer set Master toggle") },
};

static const Button buttons[] = {
	{ ClkLtSymbol,          0,              Button1,        setlayout,      {0} },
	{ ClkLtSymbol,          0,              Button3,        setlayout,      {.v = &layouts[2]} },
	{ ClkWinTitle,          0,              Button2,        zoom,           {0} },
	{ ClkStatusText,        0,              Button2,        spawn,          {.v = termcmd } },
	{ ClkClientWin,         MODKEY,         Button1,        movemouse,      {0} },
	{ ClkClientWin,         MODKEY,         Button2,        togglefloating, {0} },
	{ ClkClientWin,         MODKEY,         Button3,        resizemouse,    {0} },
	{ ClkTagBar,            0,              Button1,        view,           {0} },
	{ ClkTagBar,            0,              Button3,        toggleview,     {0} },
	{ ClkTagBar,            MODKEY,         Button1,        tag,            {0} },
	{ ClkTagBar,            MODKEY,         Button3,        toggletag,      {0} },
};
DWMCONFIG

make clean install

# ------------------------------------------------------------
echo "==> Building st $ST_VER"
fetch_src "https://dl.suckless.org/st/st-$ST_VER.tar.gz" st "$ST_VER"
cp config.def.h config.h

sed -i 's|static char \*font = .*;|static char *font = "JetBrainsMono Nerd Font:pixelsize=18:antialias=true:autohint=true";|' config.h
sed -i 's|static int borderpx = .*;|static int borderpx = 8;|' config.h

python3 - << 'PYEOF'
import re
with open('config.h') as f:
    content = f.read()

new_colors = '''static const char *colorname[] = {
	/* 8 normal colors */
	"#15161e", "#f7768e", "#9ece6a", "#e0af68",
	"#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
	/* 8 bright colors */
	"#414868", "#f7768e", "#9ece6a", "#e0af68",
	"#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5",

	[255] = 0,

	"#7aa2f7", /* 256: cursor */
	"#414868", /* 257: reverse cursor */
	"#c0caf5", /* 258: default fg */
	"#1a1b26", /* 259: default bg */
};'''

content = re.sub(r'static const char \*colorname\[\] = \{.*?\n\};',
                 new_colors, content, flags=re.DOTALL)
with open('config.h', 'w') as f:
    f.write(content)
PYEOF

make clean install

# ------------------------------------------------------------
echo "==> Building dmenu $DMENU_VER"
fetch_src "https://dl.suckless.org/tools/dmenu-$DMENU_VER.tar.gz" dmenu "$DMENU_VER"

cat > config.h << 'DMENUCONFIG'
/* See LICENSE file for copyright and license details. */
static int topbar = 1;
static const char *fonts[] = { "JetBrainsMono Nerd Font:size=12" };
static const char *prompt      = NULL;
static const char *colors[SchemeLast][2] = {
	/*     fg         bg       */
	[SchemeNorm] = { "#565f89", "#16161e" },
	[SchemeSel]  = { "#16161e", "#7aa2f7" },
	[SchemeOut]  = { "#000000", "#00ffff" },
};
static unsigned int lines      = 0;
static const char worddelimiters[] = " ";
DMENUCONFIG

make clean install

# ------------------------------------------------------------
echo "==> Building slstatus $SLSTATUS_VER"
fetch_src "https://dl.suckless.org/tools/slstatus-$SLSTATUS_VER.tar.gz" slstatus "$SLSTATUS_VER"
cp config.def.h config.h

BAT=$(ls /sys/class/power_supply/ 2>/dev/null | grep -m1 '^BAT' || true)
if [[ -n "$BAT" ]]; then
    echo "    battery found: $BAT"
    BAT_LINE="	{ battery_perc,     \"bat %s%% | \",  \"$BAT\" },"
else
    echo "    no battery (VM/desktop), skipping battery module"
    BAT_LINE=""
fi

python3 - "$BAT_LINE" << 'PYEOF'
import re, sys
bat_line = sys.argv[1]
with open('config.h') as f:
    content = f.read()

args = "static const struct arg args[] = {\n\t/* function        format          argument */\n"
args += "\t{ run_command,      \"%s | \",      \"bar-net\" },\n"
if bat_line:
    args += bat_line + "\n"
args += "\t{ run_command,      \"vol %s%% | \",  \"amixer sget Master 2>/dev/null | grep -o '[0-9]*%' | head -1 | tr -d %\" },\n"
args += "\t{ datetime,         \"%s\",           \"%a %d %b %H:%M\" },\n};"

content = re.sub(r'static const struct arg args\[\] = \{.*?\n\};',
                 lambda m: args, content, flags=re.DOTALL)
with open('config.h', 'w') as f:
    f.write(content)
PYEOF

make clean install

# ------------------------------------------------------------
echo "==> Building slock $SLOCK_VER (+ blurred desktop & dwm logo, if patch applies)"
fetch_src "https://dl.suckless.org/tools/slock-$SLOCK_VER.tar.gz" slock "$SLOCK_VER"

wget -q https://tools.suckless.org/slock/patches/foreground-and-background/slock-foreground-and-background-20210611-35633d4.diff -O fg-bg.diff
if patch -p1 --dry-run < fg-bg.diff >/dev/null 2>&1; then
    patch -p1 < fg-bg.diff
    echo "    foreground-and-background patch applied"
else
    echo "    WARN: patch doesn't apply to slock $SLOCK_VER, building plain slock"
fi
rm -f fg-bg.diff

cp config.def.h config.h
python3 - << 'PYEOF'
import re
with open('config.h') as f:
    c = f.read()
# logo idle = dim, typing = accent, wrong = red (plain slock: whole screen)
c = re.sub(r'\[INIT\]\s*=\s*"[^"]*"',   '[INIT] =   "#565f89"', c)
c = re.sub(r'\[INPUT\]\s*=\s*"[^"]*"',  '[INPUT] =  "#7aa2f7"', c)
c = re.sub(r'\[FAILED\]\s*=\s*"[^"]*"', '[FAILED] = "#f7768e"', c)
c = re.sub(r'logosize\s*=\s*\d+', 'logosize = 40', c)
c = re.sub(r'blurRadius\s*=\s*\d+', 'blurRadius=10', c)
with open('config.h', 'w') as f:
    f.write(c)
PYEOF
make clean install

# ------------------------------------------------------------
echo "==> Quiet boot + Tokyo Night console palette"
# 16-color VT palette (same colors as st), applies to tty + tuigreet
VT_RED="26,247,158,224,122,187,125,169,65,247,158,224,122,187,125,192"
VT_GRN="27,118,206,175,162,154,207,177,72,118,206,175,162,154,207,202"
VT_BLU="38,142,106,104,247,247,255,214,104,142,106,104,247,247,255,245"
CMDLINE="quiet console=tty2 loglevel=3 vt.default_red=$VT_RED vt.default_grn=$VT_GRN vt.default_blu=$VT_BLU"
sed -i \
    -e 's/^#\?GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' \
    -e "s/^#\\?GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"$CMDLINE\"/" \
    /etc/default/grub
# drop "Loading Linux ..." / "Loading initial ramdisk ..." lines
sed -i '/echo.*\$message.*grub_quote/d' /etc/grub.d/10_linux
# initramfs with only modules this machine needs -> smaller, loads faster
# (rebuilt by update-initramfs further down)
sed -i 's/^MODULES=.*/MODULES=dep/' /etc/initramfs-tools/initramfs.conf
grep -q '^GRUB_TIMEOUT_STYLE=' /etc/default/grub \
    && sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub \
    || echo 'GRUB_TIMEOUT_STYLE=hidden' >> /etc/default/grub
update-grub

# ------------------------------------------------------------
echo "==> Checking for Hyper-V framebuffer quirk"
if lsmod | grep -q hyperv_drm && [[ -e /dev/dri/card0 ]]; then
    echo "    Hyper-V detected, forcing modesetting driver"
    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/xorg.conf.d/20-modesetting.conf << 'EOF'
Section "Device"
    Identifier "Card0"
    Driver "modesetting"
    Option "kmsdev" "/dev/dri/card0"
EndSection
EOF
else
    echo "    not Hyper-V, skipping"
fi

# ------------------------------------------------------------
echo "==> Writing $USER_HOME/.xinitrc"
cat > "$USER_HOME/.xinitrc" << 'EOF'
slstatus &
while true; do dwm; done
EOF
chown "$TARGET_USER":"$TARGET_USER" "$USER_HOME/.xinitrc"

# no autologin — remove override if a previous run created it
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
rmdir /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true

# old startx-on-tty1 hook from previous runs — greetd handles this now
PROFILE="$USER_HOME/.bash_profile"
if [[ -f "$PROFILE" ]]; then
    sed -i '/^if \[ -z "\$DISPLAY" \] && \[ "\$(tty)" = "\/dev\/tty1" \]; then$/,/^fi$/d' "$PROFILE"
fi

echo "==> Console font (Terminus — VT can't do TTF/Nerd fonts)"
apt install -y console-setup
sed -i \
    -e 's/^FONTFACE=.*/FONTFACE="Terminus"/' \
    -e 's/^FONTSIZE=.*/FONTSIZE="12x24"/' \
    /etc/default/console-setup
setupcon --force 2>/dev/null || true
update-initramfs -u

echo "==> Setting up greetd + tuigreet login"
# vt 7: on tty1 it fights with getty@tty1 (Debian greetd unit does not conflict with it)
apt install -y greetd tuigreet
GREETER_USER=$(getent passwd _greetd >/dev/null && echo _greetd || echo greeter)
cat > /etc/greetd/config.toml << EOF
[terminal]
vt = 7

[default_session]
command = "tuigreet --time --remember --asterisks --width 50 --theme 'border=blue;title=blue;text=white;prompt=blue;input=white;time=gray;action=gray;button=blue;container=black' --cmd startx"
user = "$GREETER_USER"
EOF
systemctl daemon-reload
systemctl enable greetd

# ------------------------------------------------------------
echo "==> Trimming boot services"
apt purge -y modemmanager || true
systemctl mask systemd-binfmt.service
systemctl disable NetworkManager-wait-online.service 2>/dev/null || true

# ------------------------------------------------------------
echo "==> Unmuting audio (no-op if there's no sound card)"
amixer -q sset Master unmute 2>/dev/null || true
amixer -q sset Master 60% 2>/dev/null || true
alsactl store 2>/dev/null || true

echo ""
echo "============================================"
echo " Done. Reboot, log in via tuigreet -> dwm starts."
echo "   systemctl reboot"
echo "============================================"
