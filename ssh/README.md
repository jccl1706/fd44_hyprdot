# ssh notes

`~/.ssh/config` is **not** tracked here, and that is deliberate: the key
filenames differ per machine, so one file cannot be linked to both laptops
without breaking one of them. These are the two arrangements worth
remembering, written down because both were arrived at the hard way.

## Two operating systems on one address

The T480 dual-booted briefly - Fedora on the Samsung NVMe, FreeBSD on the SK
hynix - and the arrangement is written down because it applies to any second
system on that second disk, which is still empty and waiting for one.
Same NIC, so DHCP hands both the same lease - `192.168.10.172` - and each
presents its own host key. With a shared `known_hosts`, every reboot into the
other OS looks like the host key changed, and ssh refuses to connect with
`REMOTE HOST IDENTIFICATION HAS CHANGED`.

Giving each its own file lets both be remembered at once:

```
Host t480
    HostName 192.168.10.172
    UserKnownHostsFile ~/.ssh/known_hosts.t480-fedora

Host t480other
    HostName 192.168.10.172
    UserKnownHostsFile ~/.ssh/known_hosts.t480-other
```

This is not "trust anything on that address". They are two separate identities
that happen to share a lease, and a genuine key change on either is still
caught.

## A literal % in HostName must be doubled

An IPv6 link-local address carries a scope - `fe80::8e16:45ff:fe90:f6c8%em0` -
because it is only meaningful on one interface. ssh runs `HostName` through
percent-expansion, so a single `%` starts a token, and `%w` is not one:

```
vdollar_percent_expand: unknown key %w
percent_expand: failed
```

The entry then expands to nothing and the failure does not name the line that
caused it. Written `%%em0` it works. Only needed while a host has no IPv4
address - FreeBSD does IPv6 SLAAC unasked but wants `ifconfig_em0="DHCP"` in
`rc.conf` for v4, which an install that skips the network screen never writes.

## Authorising a key without a password

`https://github.com/<user>.keys` serves the public keys GitHub holds for an
account. On a machine with no keys yet - a fresh install, or an installer
running from RAM - that is enough to get in without setting a password or
reading one out loud:

```
mkdir -p ~/.ssh
fetch -o ~/.ssh/authorized_keys https://github.com/<user>.keys   # curl on Linux
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
```

It is how a machine with no keys of its own is reached for the first time -
a fresh install, or an installer running from RAM with nothing on disk yet.
