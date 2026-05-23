import { useState, type FC } from 'react';
import { PageHero } from '../components/PageHero';
import { Reveal } from '../components/Reveal';
import './Build.css';

type Tab = 'docker' | 'alpine' | 'qemu';

const TABS: { id: Tab; label: string }[] = [
  { id: 'docker', label: 'Docker' },
  { id: 'alpine', label: 'Alpine Native' },
  { id: 'qemu', label: 'Test in QEMU' },
];

const PANELS: Record<Tab, { title: string; code: string }> = {
  docker: {
    title: 'Terminal',
    code: `git clone https://github.com/kelvinzer0/superlite-os.git
cd superlite-os
./build.sh --docker`,
  },
  alpine: {
    title: 'Alpine Linux',
    code: `# On an Alpine system:
./build.sh

# Or set up environment only:
./build.sh --setup-only
cd /root/aports/scripts
./mkimage.sh --profile superlite \\
  --arch x86_64 --outdir ~/iso/ --tag latest`,
  },
  qemu: {
    title: 'QEMU',
    code: `# Simple mode (serial console)
./run-qemu-simple.sh

# Full mode with GUI
./run-qemu.sh --memory 2G --gui

# Debug mode with tmux
./run-qemu-debug.sh`,
  },
};

export const Build: FC = () => {
  const [active, setActive] = useState<Tab>('docker');
  const panel = PANELS[active];

  return (
    <>
      <PageHero eyebrow="Quick Start" subtitle="Docker or native Alpine. Under 15 minutes.">
        Build it yourself.
      </PageHero>

      <section className="section">
        <div className="container">
          <Reveal>
            <div className="build__wrapper">
              <div className="build__tabs">
                {TABS.map((tab) => (
                  <button
                    key={tab.id}
                    className={`build__tab${active === tab.id ? ' build__tab--active' : ''}`}
                    onClick={() => setActive(tab.id)}
                  >
                    {tab.label}
                  </button>
                ))}
              </div>

              <div className="build__panel">
                <div className="terminal">
                  <div className="terminal__bar">
                    <span className="terminal__dot terminal__dot--r" />
                    <span className="terminal__dot terminal__dot--y" />
                    <span className="terminal__dot terminal__dot--g" />
                    <span className="terminal__bar-title">{panel.title}</span>
                  </div>
                  <div className="terminal__body">
                    {panel.code.split('\n').map((line, i) => (
                      <div key={i} className="term-line">
                        {line.startsWith('#') ? (
                          <span className="term-line--dim">{line}</span>
                        ) : (
                          <>
                            <span className="term-prompt">$ </span>
                            {line}
                          </>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            </div>
          </Reveal>
        </div>
      </section>
    </>
  );
};
