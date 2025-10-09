document.addEventListener('DOMContentLoaded', () => {
  const yearEl = document.getElementById('year');
  if (yearEl) {
    yearEl.textContent = new Date().getFullYear();
  }

  const menuToggle = document.querySelector('.menu-toggle');
  const nav = document.getElementById('main-nav');
  if (menuToggle && nav) {
    menuToggle.addEventListener('click', () => {
      nav.classList.toggle('open');
    });

    nav.querySelectorAll('a').forEach((link) => {
      link.addEventListener('click', () => {
        nav.classList.remove('open');
      });
    });
  }

  const statsEndpoint = 'https://us-central1-splyt-4801c.cloudfunctions.net/publicStats';

  const statElements = {
    totalTrips: document.getElementById('stat-total-trips'),
    activeTrips: document.getElementById('stat-active-trips'),
    recentTrips: document.getElementById('stat-recent-trips'),
    metricTotalTrips: document.getElementById('metric-total-trips'),
    metricActiveTrips: document.getElementById('metric-active-trips'),
    metricRecentTrips: document.getElementById('metric-recent-trips'),
  };

  const hasStatElements = Object.values(statElements).some((el) => el);

  if (hasStatElements) {
    fetch(statsEndpoint)
      .then(async (response) => {
        if (!response.ok) {
          throw new Error(`Stats request failed: ${response.status}`);
        }
        return response.json();
      })
      .then((data) => {
        const compactFormatter = new Intl.NumberFormat('en-US', { notation: 'compact' });
        const fullFormatter = new Intl.NumberFormat('en-US');

        const total = Number(data.trips ?? 0);
        const active = Number(data.activeTrips ?? 0);
        const recent = Number(data.recentTrips ?? 0);

        if (statElements.totalTrips) statElements.totalTrips.textContent = compactFormatter.format(total);
        if (statElements.activeTrips) statElements.activeTrips.textContent = compactFormatter.format(active);
        if (statElements.recentTrips) statElements.recentTrips.textContent = compactFormatter.format(recent);

        if (statElements.metricTotalTrips) statElements.metricTotalTrips.textContent = fullFormatter.format(total);
        if (statElements.metricActiveTrips) statElements.metricActiveTrips.textContent = fullFormatter.format(active);
        if (statElements.metricRecentTrips) statElements.metricRecentTrips.textContent = fullFormatter.format(recent);
      })
      .catch((error) => {
        console.warn('Unable to load live stats', error);
        if (statElements.totalTrips) statElements.totalTrips.textContent = '—';
        if (statElements.activeTrips) statElements.activeTrips.textContent = '—';
        if (statElements.recentTrips) statElements.recentTrips.textContent = '—';
        if (statElements.metricTotalTrips) statElements.metricTotalTrips.textContent = '—';
        if (statElements.metricActiveTrips) statElements.metricActiveTrips.textContent = '—';
        if (statElements.metricRecentTrips) statElements.metricRecentTrips.textContent = '—';
      });
  }
});
