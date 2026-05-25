if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('service-worker.js', { updateViaCache: 'none' })
        .catch(function (err) {
            console.error('Service worker registration failed:', err);
        });
}
