import type { FC } from 'react';
import { Link } from 'react-router-dom';
import { Reveal } from '../components/Reveal';
import './Home.css';

interface BarDef {
  name: string;
  size: string;
  w: number;
  cls: string;
  highlight?: boolean;
}

const BARS: BarDef[] = [
  { name: 'Windows 11', size: '~20 GB', w: 100, cls: 'bar--windows' },
  { name: 'Ubuntu Desktop', size: '~4.5 GB', w: 22.5, cls: 'bar--ubuntu' },
  { name: 'node:22 Docker Image', size: '~1.1 GB', w: 5.5, cls: 'bar--docker' },
  { name: 'SuperLite OS', size: '~300 MB', w: 1.5, cls: 'bar--superlite', highlight: true },
  { name: 'Alpine base (no desktop)', size: '~50 MB', w: 0.25, cls: 'bar--alpine' },
];

export const Home: FC = () => (
  <>
    {/* Hero */}
    <header className="hero">
      <div className="hero__bg" />
      <div className="hero__content">
        <div className="hero__tag">
          <span className="hero__dot" />
          Open Source &middot; MIT License &middot; Fully Free
        </div>
        <h1 className="hero__title">
          A full Linux desktop<br />
          in <span className="hero__size">300MB</span>.
        </h1>
        <p className="hero__sub">
          Alpine Linux. LabWC Wayland. Google Chrome. File manager. Notifications.<br />
          Everything you need. Nothing you don't. Builds in 5 minutes.
        </p>
        <div className="hero__actions">
          <a
            href="https://github.com/kelvinzer0/superlite-os/releases"
            className="btn btn--primary"
            target="_blank"
            rel="noopener"
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
              <polyline points="7 10 12 15 17 10" />
              <line x1="12" y1="15" x2="12" y2="3" />
            </svg>
            Download ISO
          </a>
          <Link to="/build" className="btn btn--ghost">
            Build from source &rarr;
          </Link>
        </div>
        <div className="hero__badge">
          <a href="https://github.com/kelvinzer0/superlite-os/actions/workflows/build.yml" target="_blank" rel="noopener">
            <img src="https://github.com/kelvinzer0/superlite-os/actions/workflows/build.yml/badge.svg" alt="Build Status" />
          </a>
        </div>
      </div>
    </header>

    {/* Size comparison */}
    <section className="section" id="compare">
      <div className="container">
        <Reveal className="compare__header">
          <span className="eyebrow">The Numbers</span>
          <h2>Smaller than your Docker image.</h2>
        </Reveal>
        <div className="compare__grid">
          {BARS.map((bar) => (
            <Reveal key={bar.name}>
              <div className={`compare__bar${bar.highlight ? ' compare__bar--hl' : ''}`}>
                <div className="compare__bar-label">
                  <span className="compare__bar-name">{bar.name}</span>
                  <span className="compare__bar-size">{bar.size}</span>
                </div>
                <div className="compare__bar-track">
                  <div className={`compare__bar-fill ${bar.cls}`} style={{ width: `${bar.w}%` }} />
                </div>
                {bar.highlight && <span className="compare__bar-arrow">&larr; This one</span>}
              </div>
            </Reveal>
          ))}
        </div>
        <p className="compare__note">Full desktop. Browser. File manager. Waybar. Notifications. Theme. Font.</p>
      </div>
    </section>

    {/* Screenshot */}
    <section className="section section--dark">
      <div className="container">
        <Reveal className="screenshot__header">
          <span className="eyebrow">The Desktop</span>
          <h2>This is what 300MB looks like.</h2>
          <p>Catppuccin Mocha. Three-panel Waybar. LabWC compositor. Foot terminal.</p>
        </Reveal>
        <Reveal>
          <div className="screenshot__frame">
            <div className="screenshot__bar">
              <div className="screenshot__dots">
                <span className="screenshot__dot screenshot__dot--red" />
                <span className="screenshot__dot screenshot__dot--yellow" />
                <span className="screenshot__dot screenshot__dot--green" />
              </div>
              <span className="screenshot__title">SuperLite OS</span>
            </div>
            <img src="/superlite-os/screenshot.png" alt="SuperLite OS desktop" loading="lazy" />
          </div>
        </Reveal>
      </div>
    </section>

    {/* CTA */}
    <section className="section cta">
      <div className="container">
        <h2>Stop building build systems.<br />Start building OSes.</h2>
        <p>Clone. Build. Boot. Under 15 minutes.</p>
        <div className="cta__actions">
          <a href="https://github.com/kelvinzer0/superlite-os/releases" className="btn btn--primary btn--lg" target="_blank" rel="noopener">
            Download ISO
          </a>
          <a href="https://github.com/kelvinzer0/superlite-os" className="btn btn--ghost btn--lg" target="_blank" rel="noopener">
            Star on GitHub
          </a>
        </div>
      </div>
    </section>
  </>
);
