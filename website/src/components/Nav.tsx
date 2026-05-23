import { useState, useEffect, type FC } from 'react';
import { Link, useLocation } from 'react-router-dom';
import './Nav.css';

const NAV_ITEMS = [
  { to: '/', label: 'Home' },
  { to: '/features', label: 'Features' },
  { to: '/stack', label: 'Stack' },
  { to: '/shortcuts', label: 'Shortcuts' },
  { to: '/build', label: 'Build' },
] as const;

export const Nav: FC = () => {
  const [open, setOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  const { pathname } = useLocation();

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 60);
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  useEffect(() => {
    setOpen(false);
  }, [pathname]);

  return (
    <nav className={`nav${scrolled ? ' nav--scrolled' : ''}`}>
      <div className="nav__inner">
        <Link to="/" className="nav__logo">
          <span className="nav__glyph">S</span>
          <span>SuperLite</span>
        </Link>

        <div className={`nav__links${open ? ' nav__links--open' : ''}`}>
          {NAV_ITEMS.map(({ to, label }) => (
            <Link
              key={to}
              to={to}
              className={`nav__link${pathname === to ? ' nav__link--active' : ''}`}
            >
              {label}
            </Link>
          ))}
        </div>

        <a
          href="https://github.com/kelvinzer0/superlite-os/releases"
          className="nav__cta"
          target="_blank"
          rel="noopener"
        >
          Download
        </a>

        <button
          className="nav__toggle"
          aria-label="Toggle menu"
          onClick={() => setOpen((v) => !v)}
        >
          <span /><span /><span />
        </button>
      </div>
    </nav>
  );
};
