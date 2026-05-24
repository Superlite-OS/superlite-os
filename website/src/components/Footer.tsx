import type { FC } from 'react';
import './Footer.css';

export const Footer: FC = () => (
  <footer className="footer">
    <div className="footer__inner">
      <div className="footer__brand">
        <span className="footer__glyph">S</span>
        <span>SuperLite OS</span>
      </div>
      <div className="footer__links">
        <a href="https://github.com/Superlite-OS/superlite-os" target="_blank" rel="noopener"><i className="fa-brands fa-github" /> GitHub</a>
        <a href="https://github.com/Superlite-OS/superlite-os/releases" target="_blank" rel="noopener"><i className="fa-solid fa-tag" /> Releases</a>
        <a href="https://github.com/Superlite-OS/superlite-os/actions" target="_blank" rel="noopener"><i className="fa-solid fa-rotate" /> CI/CD</a>
      </div>
      <div className="footer__copy">MIT &middot; Built on Alpine Linux</div>
    </div>
  </footer>
);
