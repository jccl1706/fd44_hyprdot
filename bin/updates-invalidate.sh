#!/usr/bin/env bash
# =========================================================================
# updates-invalidate.sh - tell the bar its update count is out of date
# =========================================================================
#
# Run by dnf/fd44-updates.actions after every dnf5 transaction.
#
# WHY IT DELETES A CACHE RATHER THAN REFRESHING ONE. bin/updates.py keeps its
# answer in ~/.cache/updates/list.json and trusts it for an hour, so the bar can
# answer instantly instead of waiting on dnf. That is the right trade for a
# status icon - but it means an upgrade run from a terminal leaves the pill
# showing the old number until the hour is up. Measured: 68 packages still shown
# after the machine had been fully updated.
#
# A dnf hook runs as ROOT. `updates.py check` as root would write root's cache,
# in /root/.cache, which the bar never reads - the count would stay wrong and
# the hook would look like it worked. So this removes the user's cache instead,
# and updates.py does the rest: with no cache, `status` answers "unknown" (the
# bar draws nothing) and spawns a real check in the background, as the user who
# owns the session. The right number appears a second or two later.
#
# A BRIEF BLANK, NOT A WRONG NUMBER, which is the better failure for an icon
# whose whole job is to tell you whether anything is waiting.

set -euo pipefail

# Only regular files, and only this exact path under each home. A dnf hook runs
# as root over whatever is in /home, so it names what it removes precisely
# rather than globbing a directory.
shopt -s nullglob
for cache in /home/*/.cache/updates/list.json /root/.cache/updates/list.json; do
    [[ -f $cache ]] || continue
    rm -f -- "$cache"
done
exit 0
