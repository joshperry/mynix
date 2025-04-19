#!/usr/bin/env bash

# Example locker script -- demonstrates how to use the --transfer-sleep-lock
# option with i3lock's forking mode to delay sleep until the screen is locked.

## CONFIGURATION ##############################################################
BLANK='#ffffff88'
CLEAR='#ffffff22'
DEFAULT='#d65d0ed0'
TEXT='#000000ee'
WRONG='#880000bb'
VERIFYING='#bbbbbbbb'

# Options to pass to i3lock
i3lock_options=(
--insidever-color=$CLEAR
--ringver-color=$VERIFYING
--insidewrong-color=$CLEAR
--ringwrong-color=$WRONG
--inside-color=$BLANK
--ring-color=$DEFAULT
--line-uses-inside
--separator-color=$DEFAULT
--verif-color=$TEXT
--wrong-color=$TEXT
--time-color=#ffffffff
--date-color=$TEXT
--layout-color=#00000000
--keyhl-color=$WRONG
--bshl-color=$WRONG
--time-size=68
--time-font="Inconsolata:style=Bold"
--date-font="Sauce Code Powerline:style=Bold"
--layout-font="Sauce Code Powerline:style=Bold"
--timeoutline-color=$TEXT
--timeoutline-width=1.5
--radius 180
--ring-width 40
--screen 1
--blur 8
--ignore-empty-password
--clock
--indicator
--time-str="%H:%M:%S"
--date-str="%A, %B %d"
--keylayout 1
)

# Run before starting the locker
pre_lock() {
  # Sleep the monitors after 10s
  xset dpms 300 300 600
  return
}

# Run after the locker exits
post_lock() {
  # Disable dpms timeouts, logind/screensaver timeout handles sleep
  xset dpms 0 0 0
  return
}

###############################################################################

pre_lock

# We set a trap to kill the locker if we get killed, then start the locker and
# wait for it to exit. The waiting is not that straightforward when the locker
# forks, so we use this polling only if we have a sleep lock to deal with.
if [[ -e /dev/fd/${XSS_SLEEP_LOCK_FD:--1} ]]; then
    kill_i3lock() {
        pkill -xu $EUID "$@" i3lock-color
    }

    trap kill_i3lock TERM INT

    # we have to make sure the locker does not inherit a copy of the lock fd
    i3lock-color "${i3lock_options[@]}" {XSS_SLEEP_LOCK_FD}<&-

    # now close our fd (only remaining copy) to indicate we're ready to sleep
    exec {XSS_SLEEP_LOCK_FD}<&-

    while kill_i3lock -0; do
        sleep 0.5
    done
else
    trap 'kill %%' TERM INT
    i3lock-color -n "${i3lock_options[@]}" &
    wait
fi

post_lock
