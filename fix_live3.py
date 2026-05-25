import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.168.1.14', username='root', password='kelvin123', timeout=10)

def r(cmd, t=15):
    i, o, e = ssh.exec_command(cmd, timeout=t)
    return o.read().decode('utf-8', errors='replace').strip()

# 1. Extract libsystemd0 with python ar
print(r('python3 -c "import struct; f=open(\'/tmp/libsystemd0.deb\',\'rb\'); f.read(8); hdr=f.read(48); sz=int(hdr[40:48].strip()); f.read(sz+sz%2); hdr2=f.read(48); sz2=int(hdr2[40:48].strip()); open(\'/tmp/d.tar\',\'wb\').write(f.read(sz2)); print(\'OK\')" 2>&1'))

# 2. Extract tar
print(r('cd /tmp && tar xf d.tar 2>&1 && find /tmp/lib -name "libsystemd*" 2>/dev/null'))

# 3. Copy
print(r('cp /tmp/lib/x86_64-linux-gnu/libsystemd.so.0* /usr/lib/glibc/ 2>&1 && ls /usr/lib/glibc/libsystemd*'))

# 4. Test all
print('terax:', r('/bin/terax --version 2>&1')[:80])

# 5. Chrome - check where it is
print('chrome paths:', r('ls -la /opt/google/chrome/chrome /usr/bin/google-chrome-stable 2>&1'))

# 6. doublecmd - check wrapper
print('doublecmd:', r('readlink -f /bin/doublecmd 2>&1'))

# 7. curl - check file type
print('curl file:', r('file /usr/local/lib/curl-impersonate/curl-impersonate-chrome 2>&1'))

ssh.close()
