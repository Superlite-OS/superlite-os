#!/usr/bin/env python3
import tarfile, io, os, lzma, gzip, shutil

def extract_deb(deb_path, output_dir, filter_name):
    with open(deb_path, 'rb') as f:
        magic = f.read(8)
        if magic != b'!<arch>\n':
            return
        while True:
            header = f.read(60)
            if len(header) < 60:
                break
            name = header[0:16].strip().decode()
            size = int(header[48:58].strip())
            if 'data.tar' in name:
                data = f.read(size)
                if '.xz' in name:
                    data = lzma.decompress(data)
                elif '.gz' in name:
                    data = gzip.decompress(data)
                tf = tarfile.open(fileobj=io.BytesIO(data))
                for m in tf.getmembers():
                    if filter_name in m.name and m.isfile():
                        print('  Extracting: ' + m.name)
                        tf.extract(m, output_dir)
                break
            else:
                f.read(size + (size % 2))

print('Extracting liblzma5...')
os.makedirs('/tmp/lzma-ext', exist_ok=True)
extract_deb('/tmp/liblzma5.deb', '/tmp/lzma-ext', 'liblzma')
for root, dirs, files in os.walk('/tmp/lzma-ext'):
    for f in files:
        if 'liblzma' in f:
            src = os.path.join(root, f)
            dst = '/usr/local/lib/glibc-extra/' + f
            print('  Copying ' + f)
            shutil.copy2(src, dst)

print('Extracting libhwy1...')
os.makedirs('/tmp/hwy-ext', exist_ok=True)
extract_deb('/tmp/libhwy.deb', '/tmp/hwy-ext', 'libhwy')
for f in ['libhwy.so.1', 'libhwy.so.1.3.0', 'libhwy.so.1.0.3']:
    p = '/usr/local/lib/glibc-extra/' + f
    if os.path.exists(p):
        os.remove(p)
for root, dirs, files in os.walk('/tmp/hwy-ext'):
    for f in files:
        if 'libhwy' in f:
            src = os.path.join(root, f)
            dst = '/usr/local/lib/glibc-extra/' + f
            print('  Copying ' + f)
            shutil.copy2(src, dst)

print('Contents:')
for f in sorted(os.listdir('/usr/local/lib/glibc-extra')):
    print('  ' + f)
shutil.rmtree('/tmp/lzma-ext', ignore_errors=True)
shutil.rmtree('/tmp/hwy-ext', ignore_errors=True)
print('Done!')
