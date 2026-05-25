import paramiko
ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect('192.168.1.14', username='root', password='kelvin123', timeout=10)

def r(cmd, t=30):
    i, o, e = ssh.exec_command(cmd, timeout=t)
    return o.read().decode('utf-8', errors='replace').strip()

# 1. Extract libsystemd0
r('mkdir -p /tmp/lsd')
r('cd /tmp/lsd && ar x /tmp/libsystemd0.deb 2>/dev/null || true')
# Try python extraction
r("python3 -c \"import tarfile,io; f=open('/tmp/libsystemd0.deb','rb'); d=f.read(); i=d.find(b'data.tar'); tarfile.open(fileobj=io.BytesIO(d[i:])).extractall('/tmp/lsd')\" 2>/dev/null || true")

# 2. Copy libsystemd to glibc dir
result = r('cp /tmp/lsd/lib/x86_64-linux-gnu/libsystemd.so.0* /usr/lib/glibc/ 2>/dev/null; ls /usr/lib/glibc/libsystemd* 2>/dev/null || echo NOT_FOUND')
print(f'libsystemd: {result}')

# 3. Test terax
result = r('/bin/terax --version 2>&1')
print(f'terax: {result[:100]}')

# 4. Test doublecmd
result = r('/bin/doublecmd --version 2>&1')
print(f'doublecmd: {result[:100]}')

# 5. Test Chrome
result = r('/usr/bin/google-chrome-stable --version 2>&1')
print(f'chrome: {result[:100]}')

# 6. Test curl-impersonate
result = r('/usr/local/bin/curl-impersonate-chrome --version 2>&1')
print(f'curl: {result[:100]}')

ssh.close()
