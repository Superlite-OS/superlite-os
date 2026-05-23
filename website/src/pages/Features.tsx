import type { FC, ReactNode } from 'react';
import { PageHero } from '../components/PageHero';
import { Reveal } from '../components/Reveal';
import './Features.css';

const parseInlineCode = (html: string): ReactNode[] => {
  const parts = html.split(/(<code>.*?<\/code>)/g);
  return parts.map((part, i) => {
    const m = part.match(/^<code>(.*?)<\/code>$/);
    return m ? <code key={i}>{m[1]}</code> : part;
  });
};

interface FeatureDetailProps {
  num: string;
  icon: string;
  title: string;
  description: string;
  details: string[];
  terminal: { lines: { text: string; type?: 'prompt' | 'dim' | 'accent' | 'green' }[] };
  reverse?: boolean;
}

const FeatureDetail: FC<FeatureDetailProps> = ({ num, icon, title, description, details, terminal, reverse }) => (
  <Reveal>
    <div className={`fd${reverse ? ' fd--reverse' : ''}`}>
      <div className="fd__text">
        <span className="fd__num">{num}</span>
        <h2 className="fd__title"><i className={icon} />{title}</h2>
        <p className="fd__desc">{parseInlineCode(description)}</p>
        <ul className="fd__list">
          {details.map((d) => <li key={d}><i className="fa-solid fa-check" /> {parseInlineCode(d)}</li>)}
        </ul>
      </div>
      <div className="fd__visual">
        <div className="terminal">
          <div className="terminal__bar">
            <span className="terminal__dot terminal__dot--r" />
            <span className="terminal__dot terminal__dot--y" />
            <span className="terminal__dot terminal__dot--g" />
          </div>
          <div className="terminal__body">
            {terminal.lines.map((l, i) => (
              <div key={i} className={`term-line${l.type ? ` term-line--${l.type}` : ''}`}>
                {l.type === 'prompt' && <span className="term-prompt">$ </span>}
                {l.text}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  </Reveal>
);

const FEATURES: FeatureDetailProps[] = [
  {
    num: '01',
    icon: 'fa-brands fa-chrome',
    title: 'Chrome on musl',
    description:
      'Running Google Chrome on pure Alpine musl libc was a war. The result: a custom glibc isolation layer that sandboxes 63 Debian Bookworm libraries at <code>/usr/lib/glibc/</code>. No VM. No container. No Flatpak.',
    details: [
      '63 glibc packages from Debian Bookworm',
      'Custom <code>zapt</code> package manager with dep resolution',
      'Per-binary ldd checks',
      'Library sandbox at <code>/usr/lib/glibc/</code>',
    ],
    terminal: {
      lines: [
        { text: 'zapt install google-chrome', type: 'prompt' },
        { text: 'Resolving dependencies...', type: 'dim' },
        { text: 'Downloading 63 packages from Debian Bookworm', type: 'dim' },
        { text: 'Extracting to /usr/lib/glibc/...', type: 'dim' },
        { text: 'Generating wrapper for google-chrome', type: 'dim' },
        { text: '✓ google-chrome installed', type: 'green' },
        { text: 'google-chrome --version', type: 'prompt' },
        { text: 'Google Chrome 125.0.6422.76', type: 'accent' },
      ],
    },
  },
  {
    num: '02',
    icon: 'fa-solid fa-desktop',
    title: 'Wayland native',
    description:
      'LabWC compositor — OpenBox-style window management for Wayland. Snapping, workspaces, shading, fullscreen toggle. No X11 legacy. No XWayland dependency.',
    details: [
      'LabWC — OpenBox config syntax on Wayland',
      '3-panel Waybar: system, workspaces, controls',
      'Mako notification daemon',
      'tofi full-screen launcher',
    ],
    reverse: true,
    terminal: {
      lines: [
        { text: 'labwc --version', type: 'prompt' },
        { text: 'labwc 0.7.3', type: 'accent' },
        { text: 'echo $XDG_SESSION_TYPE', type: 'prompt' },
        { text: 'wayland', type: 'accent' },
        { text: 'wlr-randr', type: 'prompt' },
        { text: 'eDP-1 "AU Optronics 0x573D"', type: 'dim' },
        { text: '  1920x1080 px, 60.00 Hz', type: 'dim' },
      ],
    },
  },
  {
    num: '03',
    icon: 'fa-brands fa-usb',
    title: 'USB overlay',
    description:
      'Live USB boot normally runs from tmpfs — everything in RAM. Chrome alone eats 1GB+. SuperLite auto-creates an ext4 partition on first boot and uses overlayfs to redirect writes to USB storage.',
    details: [
      'Auto-creates SUPERLITE-RW ext4 partition',
      'overlayfs: read-only rootfs + USB writable layer',
      'Falls back to tmpfs if no USB partition',
      'Zero config — happens automatically',
    ],
    terminal: {
      lines: [
        { text: 'lsblk', type: 'prompt' },
        { text: 'sda   8:0    1  14.9G  0 disk', type: 'dim' },
        { text: '├─sda1  8:1    1   300M  /media/cdrom', type: 'dim' },
        { text: '└─sda3  8:3    1  14.5G  /overlay', type: 'dim' },
        { text: 'free -h', type: 'prompt' },
        { text: 'Mem: 1.9G total, 1.4G free', type: 'green' },
      ],
    },
  },
  {
    num: '04',
    icon: 'fa-solid fa-hard-drive',
    title: 'Offline installer',
    description:
      'Went through three lives: Go, Calamares (removed from Alpine repos after v3.19), and finally Python + tofi GUI. Each rewrite taught something the previous one couldn\'t.',
    details: [
      'Python + tofi full-screen GUI',
      'Tar pipe copy from live USB',
      'Prebuilt bootloader with GRUB chroot + fallback',
      'sfdisk partitioning (GPT, proper UUIDs)',
      'Completely offline',
    ],
    reverse: true,
    terminal: {
      lines: [
        { text: 'superlite-installer', type: 'prompt' },
        { text: 'Detecting disks...', type: 'dim' },
        { text: '  /dev/sda  14.9G  Kingston DataTraveler', type: 'dim' },
        { text: '  /dev/sdb  238.5G  Samsung SSD 850', type: 'dim' },
        { text: '? Select target disk:', type: 'accent' },
        { text: '  > /dev/sdb  Samsung SSD 850', type: 'dim' },
        { text: 'Copying system via tar pipe...', type: 'dim' },
        { text: 'Installing bootloader...', type: 'dim' },
        { text: '✓ Installation complete', type: 'green' },
      ],
    },
  },
  {
    num: '05',
    icon: 'fa-solid fa-box-archive',
    title: 'zapt package manager',
    description:
      'A custom .deb installer built for Alpine musl. Downloads from Debian pool, resolves dependencies, extracts libraries, generates ldd-based wrappers.',
    details: [
      'Downloads from Debian pool',
      'Automatic dependency resolution',
      'apk ownership conflict detection',
      '3 install modes: full, bin-only, lib-only',
    ],
    terminal: {
      lines: [
        { text: 'zapt install doublecmd-gtk', type: 'prompt' },
        { text: 'Searching Debian pool...', type: 'dim' },
        { text: 'Found: doublecmd-gtk 1.1.0-1', type: 'dim' },
        { text: 'Dependencies: libgtk-3-0, libglib2.0-0', type: 'dim' },
        { text: 'Checking apk ownership conflicts...', type: 'dim' },
        { text: '  Skipping libglib2.0-0 (owned by apk)', type: 'dim' },
        { text: '✓ doublecmd-gtk installed', type: 'green' },
      ],
    },
  },
  {
    num: '06',
    icon: 'fa-solid fa-palette',
    title: 'Catppuccin Mocha',
    description:
      'Unified dark theme across every component. Evolved from WhiteSur-Light — tested, questioned, and replaced when Catppuccin proved better for adoption.',
    details: [
      'labwc window decorations',
      'Waybar 3-panel styling',
      'Mako notification popups',
      'tofi launcher + power menu',
      'GTK application theme',
      'Font Awesome 7 icon font',
    ],
    reverse: true,
    terminal: {
      lines: [
        { text: '# Palette', type: 'dim' },
        { text: 'Base:      #1E1E2E', type: 'dim' },
        { text: 'Surface:   #313244', type: 'dim' },
        { text: 'Blue:      #89B4FA', type: 'accent' },
        { text: 'Mauve:     #CBA6F7', type: 'accent' },
        { text: 'Green:     #A6E3A1', type: 'green' },
        { text: 'Red:       #F38BA8', type: 'dim' },
        { text: 'Text:      #CDD6F4', type: 'dim' },
      ],
    },
  },
];

export const Features: FC = () => (
  <div className="page-enter">
    <PageHero eyebrow={<><i className="fa-solid fa-bolt" /> Features</>} subtitle="Not a minimal install. A complete, ready-to-use system.">
      Real desktop.<br />Tiny footprint.
    </PageHero>

    <section className="section">
      <div className="container">
        <div className="fd-grid">
          {FEATURES.map((f) => <FeatureDetail key={f.num} {...f} />)}
        </div>
      </div>
    </section>

    {/* Architecture */}
    <section className="section section--dark" id="architecture">
      <div className="container">
        <Reveal className="arch__header">
          <span className="eyebrow">Architecture</span>
          <h2>3 scripts, no magic</h2>
        </Reveal>
        <Reveal>
          <div className="arch__flow">
            <div className="arch__node"><div className="arch__label">build.sh</div><div className="arch__desc">Entry point</div></div>
            <div className="arch__arrow">&darr;</div>
            <div className="arch__node"><div className="arch__label">mkimage.sh</div><div className="arch__desc">Alpine's native image builder</div></div>
            <div className="arch__arrow">&darr;</div>
            <div className="arch__branches">
              <div className="arch__node"><div className="arch__label">mkimg.superlite.sh</div><div className="arch__desc">Profile: packages, kernel</div></div>
              <span className="arch__or">+</span>
              <div className="arch__node"><div className="arch__label">genapkovl-superlite.sh</div><div className="arch__desc">Overlay: config, services</div></div>
            </div>
          </div>
        </Reveal>
        <Reveal>
          <div className="arch__compare">
            <div className="arch__card arch__card--bad card-hover">
              <h3>Yocto / BitBake</h3>
              <ul>
                <li><span className="c-red">2-6 hour</span> builds</li>
                <li><span className="c-red">50GB+</span> disk usage</li>
                <li>Layers, recipes, bitbake</li>
                <li>Custom initramfs hooks</li>
              </ul>
            </div>
            <div className="arch__card arch__card--good card-hover">
              <h3>SuperLite OS</h3>
              <ul>
                <li><span className="c-green">5-15 min</span> builds</li>
                <li><span className="c-green">&lt;1GB</span> disk usage</li>
                <li>3 shell scripts</li>
                <li>Alpine handles initramfs</li>
              </ul>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  </div>
);
