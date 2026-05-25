import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.168.1.14', username='root', password='kelvin123', timeout=10)

def r(cmd, t=30):
    i, o, e = ssh.exec_command(cmd, timeout=t)
    return o.read().decode('utf-8', errors='replace').strip()

# Issue 1: libsystemd0 extraction - try manual tar extraction
print("=== Fix 1: libsystemd0 ===")
# .deb is ar archive. data.tar.xz starts after the ar header
# ar header: 8 bytes magic + 48 bytes per entry. data.tar is usually 2nd entry
r('mkdir -p /tmp/lsd')
# Use python to extract ar properly
r("""python3 -c "
import struct, os
f = open('/tmp/libsystemd0.deb', 'rb')
magic = f.read(8)  # '!<arch>\\n'
while True:
    hdr = f.read(48)
    if len(hdr) < 48: break
    name = hdr[:16].strip()
    size = int(hdr[48-10:48-1].strip())
    if name.startswith(b'data.tar'):
        data = f.read(size)
        with open('/tmp/lsd/data.tar', 'wb') as out:
            out.write(data)
        break
    f.read(size + (size % 2))  # skip + alignment
f.close()
print('extracted data.tar', os.path.getsize('/tmp/lsd/data.tar'))
" 2>&1""")
print(r('ls -lh /tmp/lsd/data.tar 2>/dev/null'))
r('cd /tmp/lsd && tar xf data.tar 2>/dev/null')
print(r('find /tmp/lsd -name "libsystemd*" 2>/dev/null'))
r('cp /tmp/lsd/lib/x86_64-linux-gnu/libsystemd.so.0* /usr/lib/glibc/ 2>/dev/null || true')
print(r('ls /usr/lib/glibc/libsystemd* 2>/dev/null || echo STILL_NOT_FOUND'))

# Issue 2: doublecmd - check wrapper
print("\n=== Fix 2: doublecmd ===")
print(r('cat /bin/doublecmd 2>/dev/null | head -3'))
print(r('ls -la /bin/doublecmd 2>/dev/null'))
print(r('ls -la /.modloop/bin/doublecmd 2>/dev/null'))
# doublecmd uses musl ldd error - it's a symlink to /.modloop/lib/doublecmd/doublecmd
# The real binary needs libQt5Pas which IS in /usr/lib/glibc/
# But doublecmd doesn't have a glibc wrapper - it's a direct binary
print(r('file /lib/doublecmd/doublecmd 2>/dev/null'))

# Issue 3: Chrome wrapper
print("\n=== Fix 3: Chrome ===")
print(r('ls -la /usr/bin/google-chrome* /bin/google-chrome* /opt/google/chrome/chrome 2>/dev/null'))
print(r('cat /opt/google/chrome/chrome 2>/dev/null | head -3'))

# Issue 4: curl-impersonate
print("\n=== Fix 4: curl-impersonate ===")
print(r('file /usr/local/lib/curl-impersonate/curl-impersonate-chrome 2>/dev/null'))
print(r('cat /usr/local/bin/curl-impersonate-chrome 2>/dev/null | head -3'))

ssh.close()
