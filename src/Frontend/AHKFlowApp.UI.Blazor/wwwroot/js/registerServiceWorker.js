const isLocalDevelopmentHost =
    window.location.hostname === 'localhost' ||
    window.location.hostname === '127.0.0.1' ||
    window.location.hostname === '[::1]';

if ('serviceWorker' in navigator) {
    if (isLocalDevelopmentHost) {
        navigator.serviceWorker.getRegistrations()
            .then(function (registrations) {
                return Promise.all(registrations.map(function (registration) {
                    return registration.unregister();
                }));
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
