(function () {
  'use strict';

  function getTripCode() {
    const pathMatch = window.location.pathname.match(/\/join\/([A-Za-z0-9]+)/);
    if (pathMatch && pathMatch[1]) {
      return pathMatch[1];
    }

    const params = new URLSearchParams(window.location.search);
    return params.get('code') || 'Unknown';
  }

  const tripCode = getTripCode();
  const codeElement = document.getElementById('trip-code');
  const copyButton = document.getElementById('copy-button');
  const openAppLink = document.getElementById('open-app');
  const downloadLink = document.getElementById('download-app');

  if (codeElement) {
    codeElement.textContent = tripCode.toUpperCase();
  }

  const deepLink = `ledgex://join?code=${tripCode}`;
  if (openAppLink) {
    openAppLink.href = deepLink;
  }

  if (copyButton) {
    copyButton.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(tripCode);
        copyButton.textContent = 'Copied!';
        setTimeout(() => (copyButton.textContent = 'Copy code'), 2000);
      } catch (err) {
        copyButton.textContent = 'Copy failed';
      }
    });
  }

  function attemptOpen() {
    window.location.href = deepLink;
  }

  const isAppleDevice = /iphone|ipad|ipod/i.test(window.navigator.userAgent);
  if (isAppleDevice) {
    setTimeout(attemptOpen, 400);
  }

  if (openAppLink) {
    openAppLink.addEventListener('click', (event) => {
      event.preventDefault();
      attemptOpen();
    });
  }

  if (downloadLink) {
    downloadLink.href = 'https://apps.apple.com';
  }
})();
