import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.168.1.14', username='root', password='kelvin123', timeout=10)

def r(cmd, t=30):
    i, o, e = ssh.exec_command(cmd, timeout=t)
    return o.read().decode('utf-8', errors='replace').strip()

# 1. Extract libsystemd0 properly (ar format: 60-byte headers)
print(r("""python3 -c "
f=open('/tmp/libsystemd0.deb','rb')
f.read(8)  # skip !<arch>\\n
while True:
    hdr=f.read(60)
    if len(hdr)<60: break
    sz=int(hdr[48:58].strip())
    if b'data.tar' in hdr[:16]:
        open('/tmp/d.tar','wb').write(f.read(sz))
        break
    f.read(sz+sz%2)
f.close()
print('OK')
" 2>&1"""))
print(r('cd /tmp && tar xf d.tar 2>&1 && find /tmp/lib -name "libsystemd*" 2>/dev/null'))
print(r('cp /tmp/lib/x86_64-linux-gnu/libsystemd.so.0* /usr/lib/glibc/ 2>&1 && ls /usr/lib/glibc/libsystemd*'))

# 2. Test terax
print('terax:', r('/bin/terax --version 2>&1')[:100])

# 3. Chrome - check wrapper content
print('chrome wrapper:', r('cat /opt/google/chrome/chrome 2>&1')[:200])

# 4. doublecmd - check if it has a glibc wrapper
print('doublecmd wrapper:', r('cat /bin/doublecmd 2>&1 | head -3')[:200])

# 5. curl - check wrapper content
print('curl wrapper:', r('cat /usr/local/bin/curl-impersonate-chrome 2>&1 | head -3')[:200])

ssh.close()
