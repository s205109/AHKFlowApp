const isLocalDevelopmentHost =
    window.location.hostname === 'localhost' ||
    window.location.hostname === '127.0.0.1' ||
    window.location.hostname === '::1' ||
    window.location.hostname === '[::1]';
const localServiceWorkerReloadKey = 'ahkflowapp-local-sw-cleanup-reload';

if ('serviceWorker' in navigator) {
    if (isLocalDevelopmentHost) {
        // Keep localhost free of service workers because they destabilize VS Code Blazor/MSAL login debugging.
        navigator.serviceWorker.getRegistrations()
            .then(function (registrations) {
                return Promise.all(registrations.map(function (registration) {
                    return registration.unregister();
                }));
            })
            .then(function () {
                if (navigator.serviceWorker.controller && sessionStorage.getItem(localServiceWorkerReloadKey) !== 'true') {
                    sessionStorage.setItem(localServiceWorkerReloadKey, 'true');
                    window.location.reload();
                    return;
                }

                if (!navigator.serviceWorker.controller) {
                    sessionStorage.removeItem(localServiceWorkerReloadKey);
                }
            })
            .catch(function (err) {
                console.error('Service worker cleanup failed:', err);
            });
    } else {
        navigator.serviceWorker.register('service-worker.js', { updateViaCache: 'none' })
            .catch(function (err) {
                console.error('Service worker registration failed:', err);
            });
    }
}
