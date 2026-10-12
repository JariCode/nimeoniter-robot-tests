// Extra Browser library keywords for the Nimeoniter tests (CommonJS module,
// loaded with the jsextension option in common.robot). They run in the
// Playwright process, so they can intercept the page's network requests
// before the page sends them, which keywords run inside the page cannot do.

const counts = { held: 0, failed: 0 };

// Makes the backend look slow or down for the active page. Only the page's
// requests are affected; the backend itself keeps running.
//   delay: every game state request (GET /api/state) is held for 6 seconds,
//          like a server that is waking up.
//   fail:  the first two backend requests fail like a server that is down,
//          after which requests go through normally.
// CORS preflight requests (OPTIONS) are always let through unchanged.
async function simulateSlowOrDownBackend(backend, mode, page) {
  counts.held = 0;
  counts.failed = 0;
  await page.route(`${backend}/**`, async (route) => {
    const request = route.request();
    if (request.method() !== 'OPTIONS') {
      if (mode === 'delay' && request.url().includes('/api/state')) {
        counts.held += 1;
        await new Promise((resolve) => setTimeout(resolve, 6000));
      } else if (mode === 'fail' && counts.failed < 2) {
        counts.failed += 1;
        return route.abort('failed');
      }
    }
    return route.continue();
  });
}
simulateSlowOrDownBackend.rfdoc =
  'Makes the backend look slow (mode delay) or down (mode fail) for the active page.';

// Removes the simulation and returns how many requests were held and failed.
async function restoreBackend(backend, page) {
  await page.unroute(`${backend}/**`);
  return { held: counts.held, failed: counts.failed };
}
restoreBackend.rfdoc =
  'Removes the backend simulation and returns the numbers of held and failed requests.';

exports.simulateSlowOrDownBackend = simulateSlowOrDownBackend;
exports.restoreBackend = restoreBackend;