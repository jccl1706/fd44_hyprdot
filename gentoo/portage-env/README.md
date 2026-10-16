# PORTAGE_TMPDIR on tmpfs, and the packages that must not use it

30 GiB of RAM and a build tree that never touches the disk is the right trade
on this machine - except for three or four packages that will not fit.

## The tmpfs

In `/etc/fstab`:

```
tmpfs  /var/tmp/portage  tmpfs  size=16G,uid=portage,gid=portage,mode=775,noatime  0 0
```

16 G of 30 leaves room for the desktop and for the build's own memory. Going
much larger risks the kernel reclaiming the build tree under memory pressure,
which fails the build in a confusing way.

## The exceptions

`qtwebengine`, `chromium` and `firefox` unpack and build far past 16 G. The
failure is an out-of-space error hours in, which is why this is worth setting
up before the first world build rather than after it.

`/etc/portage/env/notmpfs.conf`:

```
PORTAGE_TMPDIR="/var/tmp/notmpfs"
```

`/etc/portage/package.env`:

```
dev-qt/qtwebengine          notmpfs.conf
www-client/chromium         notmpfs.conf
www-client/firefox          notmpfs.conf
dev-lang/rust               notmpfs.conf
sys-devel/gcc               notmpfs.conf
```

And `mkdir -p /var/tmp/notmpfs && chown portage:portage /var/tmp/notmpfs`.

## Better still: avoid three of them

`dev-lang/rust-bin` and `www-client/firefox-bin` cost nothing visible and save
hours. `qtwebengine` has no binary package - check whether the USE flags
actually pull it before accepting a 1-3 hour build; `plasma-meta` does not
always need it.
