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
        <a href="https://github.com/kelvinzer0/superlite-os" target="_blank" rel="noopener">GitHub</a>
        <a href="https://github.com/kelvinzer0/superlite-os/releases" target="_blank" rel="noopener">Releases</a>
        <a href="https://github.com/kelvinzer0/superlite-os/actions" target="_blank" rel="noopener">CI/CD</a>
      </div>
      <div className="footer__copy">MIT License &middot; Built with Alpine Linux</div>
    </div>
  </footer>
);
