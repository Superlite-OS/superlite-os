import { useState, useEffect, type FC } from 'react';
import { Link } from 'react-router-dom';
import { Reveal } from '../components/Reveal';
import { Counter } from '../components/Counter';
import './Home.css';

const WALLET = '0xf0555d40dbFB4e3Bf07044282B78F2fE1f51Ef72';
const GOAL = 1; // 1 ETH

const useEthBalance = () => {
  const [balance, setBalance] = useState(0);

  useEffect(() => {
    const fetchBalance = async () => {
      try {
        const res = await fetch('https://eth.llamarpc.com', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            jsonrpc: '2.0',
            method: 'eth_getBalance',
            params: [WALLET, 'latest'],
            id: 1,
          }),
        });
        const data = await res.json();
        if (data.result && typeof data.result === 'string' && data.result.startsWith('0x')) {
          const wei = parseInt(data.result, 16);
          if (!isNaN(wei)) setBalance(wei / 1e18);
        }
      } catch {
        // fallback: stay at 0
      }
    };
    fetchBalance();
    const interval = setInterval(fetchBalance, 30000);
    return () => clearInterval(interval);
  }, []);

  return balance;
};

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

export const Home: FC = () => {
  const balance = useEthBalance();
  const pct = Math.min((balance / GOAL) * 100, 100);

  return (
  <div className="page-enter">
    {/* Hero */}
    <header className="hero">
      <div className="hero__bg" />
      <div className="hero__content">
        <div className="hero__tag">
          <span className="hero__dot" />
          Open source
        </div>
        <h1 className="hero__title">
          A full Linux desktop<br />
          in <span className="hero__size gradient-text"><Counter end={300} suffix="MB" /></span>
        </h1>
        <p className="hero__sub">
          Wayland desktop, Chrome, Double Commander, notifications.<br />
          Complete system. Builds in 15 minutes.
        </p>
        <div className="hero__actions">
          <a
            href="https://github.com/Superlite-OS/superlite-os/releases"
            className="btn btn--primary"
            target="_blank"
            rel="noopener"
          >
            <i className="fa-solid fa-download" />
            Download ISO
          </a>
          <Link to="/build" className="btn btn--ghost">
            <i className="fa-solid fa-code" />
            Build from source <i className="fa-solid fa-arrow-right" />
          </Link>
        </div>
      </div>
    </header>

    {/* Size comparison */}
    <section className="section" id="compare">
      <div className="container">
        <Reveal className="compare__header">
          <span className="eyebrow"><i className="fa-solid fa-chart-simple" /> The Numbers</span>
          <h2>Smaller than your Docker image</h2>
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
        <p className="compare__note">All of this — desktop, browser, Double Commander, theme — in 300MB.</p>
      </div>
    </section>

    {/* Screenshot */}
    <section className="section section--dark">
      <div className="container">
        <Reveal className="screenshot__header">
          <span className="eyebrow"><i className="fa-solid fa-image" /> The Desktop</span>
          <h2>This is what 300MB looks like</h2>
          <p>Catppuccin Mocha theme. Three-panel Waybar. LabWC compositor.</p>
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

    {/* Support */}
    <section className="section support">
      <div className="container">
        <Reveal className="support__inner">
          <span className="eyebrow"><i className="fa-solid fa-heart" /> Support the Future</span>
          <h2>Help fund the next release</h2>
          <p className="support__text">
            SuperLite OS thrives thanks to the dedication of its developers and the generous support from users like you.
            A new version is published as soon as contributions reach the funding target.
            After each release, the counter resets and a new target is set for the next cycle.
          </p>
          <div className="support__progress">
            <div className="support__progress-header">
              <span className="support__progress-label">Next release funding</span>
              <span className="support__progress-amount">{balance.toFixed(4)} / {GOAL} ETH</span>
            </div>
            <div className="support__progress-bar">
              <div className="support__progress-fill" style={{ width: `${pct}%` }} />
            </div>
            <span className="support__progress-pct">{pct.toFixed(1)}% funded</span>
          </div>
          <div className="support__wallet">
            <div className="support__coin">
              <i className="fa-brands fa-ethereum" />
              <span>ETH</span>
            </div>
            <img
              className="support__qr"
              src="https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=0xf0555d40dbFB4e3Bf07044282B78F2fE1f51Ef72&bgcolor=0a0a0f&color=7aa2f7&margin=8"
              alt="ETH wallet QR code"
              width="180"
              height="180"
            />
          </div>
        </Reveal>
      </div>
    </section>

    {/* CTA */}
    <section className="section cta">
      <div className="container">
        <h2 className="glitch" data-text="Stop building build systems, start building OSes">Stop building build systems,<br />start building OSes</h2>
        <p>Clone. Build. Boot. Under 15 minutes.</p>
        <div className="cta__actions">
          <a href="https://github.com/Superlite-OS/superlite-os/releases" className="btn btn--primary btn--lg" target="_blank" rel="noopener">
            <i className="fa-solid fa-download" />
            Download ISO
          </a>
          <a href="https://github.com/Superlite-OS/superlite-os" className="btn btn--ghost btn--lg" target="_blank" rel="noopener">
            <i className="fa-brands fa-github" />
            Star on GitHub
          </a>
        </div>
      </div>
    </section>
  </div>
  );
};
