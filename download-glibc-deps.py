#!/usr/bin/env python3
"""
Download glibc .so dependencies for webkit2gtk from Debian bookworm.
Extracts only .so files to the target glibc directory.
Usage: python3 download-glibc-deps.py <glibc_dir> [packages.gz_path]
"""
import gzip, os, sys, urllib.request, tarfile, io, lzma, shutil

def parse_packages(packages_gz_path=None):
    if packages_gz_path and os.path.exists(packages_gz_path):
        with open(packages_gz_path, 'rb') as f:
            data = f.read()
    else:
        url = "https://deb.debian.org/debian/dists/bookworm/main/binary-amd64/Packages.gz"
        data = urllib.request.urlopen(url).read()

    pkgs = {}
    current = {}
    for line in gzip.decompress(data).decode().split('\n'):
        line = line.strip()
        if line == '':
            if current.get('Package'):
                pkgs[current['Package']] = current
            current = {}
        elif ':' in line:
            k, v = line.split(':', 1)
            current[k.strip()] = v.strip()
    if current.get('Package'):
        pkgs[current['Package']] = current
    return pkgs

def resolve_deps(pkg_name, pkgs, resolved=None):
    if resolved is None:
        resolved = set()
    if pkg_name in resolved:
        return resolved
    resolved.add(pkg_name)
    pkg = pkgs.get(pkg_name)
    if not pkg:
        return resolved
    for dep_group in pkg.get('Depends', '').split(','):
        dep = dep_group.split('|')[0].strip().split('(')[0].strip()
        if dep and dep not in resolved:
            resolve_deps(dep, pkgs, resolved)
    return resolved

def extract_so_from_deb(deb_path):
    """Extract .so files from a .deb archive. Returns list of (name, data, is_link, link_target)."""
    files = []
    with open(deb_path, 'rb') as f:
        magic = f.read(8)
        if magic != b'!<arch>\n':
            return files
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
                    if '.so' in m.name and ('lib/' in m.name or 'usr/lib/' in m.name):
                        if m.isfile():
                            files.append((os.path.basename(m.name), tf.extractfile(m).read(), False, None))
                        elif m.issym():
                            files.append((os.path.basename(m.name), None, True, m.linkname))
                break
            else:
                f.read(size + (size % 2))
    return files

def main():
    glibc_dir = sys.argv[1] if len(sys.argv) > 1 else '/usr/lib/glibc'
    packages_gz = sys.argv[2] if len(sys.argv) > 2 else None

    print(f"Target: {glibc_dir}")
    print("Parsing Packages.gz...")
    pkgs = parse_packages(packages_gz)
    print(f"  {len(pkgs)} packages")

    # Resolve deps for webkit2gtk
    needed = resolve_deps('libwebkit2gtk-4.1-0', pkgs)
    needed |= resolve_deps('libsoup-3.0-0', pkgs)

    # Filter to library packages only
    SKIP = ['-data', '-common', '-dev', 'font', 'icon', 'perl', 'adwaita',
            'hicolor', 'dictionaries', 'hunspell', 'iso-codes', 'shared-mime',
            'xkb-data', 'usrmerge', 'init-system', 'debconf', 'procps',
            'gtk-update', 'libsensors', '-config', 'emacsen']
    lib_pkgs = [p for p in sorted(needed) if p in pkgs
                and (p.startswith('lib') or p in ['zlib1g'])
                and not any(s in p for s in SKIP)]

    # Check existing .so files
    existing = set()
    for d in [glibc_dir]:
        if os.path.isdir(d):
            for f in os.listdir(d):
                if '.so' in f:
                    existing.add(f)

    print(f"  {len(lib_pkgs)} library packages to check")
    print(f"  {len(existing)} existing .so files")

    # Download and extract
    tmpdir = '/tmp/glibc-deps'
    os.makedirs(tmpdir, exist_ok=True)

    installed = 0
    skipped = 0
    for i, pkg in enumerate(lib_pkgs):
        filename = pkgs[pkg].get('Filename', '')
        if not filename:
            continue

        # Check if we already have the main .so
        so_guess = pkg.split('0')[0].split('1')[0].split('2')[0].split('3')[0]
        if any(so_guess in f for f in existing):
            skipped += 1
            continue

        deb_path = os.path.join(tmpdir, f'{pkg}.deb')
        url = f'https://deb.debian.org/debian/{filename}'

        try:
            urllib.request.urlretrieve(url, deb_path)
        except Exception as e:
            print(f"  [{i+1}/{len(lib_pkgs)}] FAIL {pkg}: {e}")
            continue

        files = extract_so_from_deb(deb_path)
        count = 0
        for fname, data, is_link, link_target in files:
            dest = os.path.join(glibc_dir, fname)
            if os.path.exists(dest):
                continue
            if is_link:
                os.symlink(link_target, dest)
            else:
                with open(dest, 'wb') as f:
                    f.write(data)
            existing.add(fname)
            count += 1

        if count > 0:
            print(f"  [{i+1}/{len(lib_pkgs)}] {pkg}: {count} files")
            installed += 1

        os.remove(deb_path)

    # Create missing symlinks for major versions
    for f in list(existing):
        if '.so.' in f and not os.path.islink(os.path.join(glibc_dir, f)):
            parts = f.split('.so.')
            if len(parts) == 2:
                ver_parts = parts[1].split('.')
                for i in range(1, len(ver_parts)):
                    link = parts[0] + '.so.' + '.'.join(ver_parts[:i])
                    link_path = os.path.join(glibc_dir, link)
                    if not os.path.exists(link_path):
                        os.symlink(f, link_path)

    shutil.rmtree(tmpdir, ignore_errors=True)
    print(f"\nDone: {installed} packages installed, {skipped} skipped (already present)")

if __name__ == '__main__':
    main()
