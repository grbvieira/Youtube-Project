// Injetado no inicio de cada pagina. Envia ao app (handler "ytpipMedia") eventos de play/pause/PiP.
// Os eventos de midia nao propagam (bubble), por isso sao escutados na fase de captura.
(() => {
    if (window.__ytpipMediaEvents) return;
    window.__ytpipMediaEvents = true;

    // O buffer padrao (~250 entradas) enche rapido e congela a lista de recursos.
    try { performance.setResourceTimingBufferSize(2000); } catch (error) {}

    const post = (payload) => {
        try { window.webkit.messageHandlers.ytpipMedia.postMessage(payload); } catch (error) {}
    };
    const urlVideoID = () => {
        try {
            const url = new URL(window.location.href);
            const parts = url.pathname.split('/');
            return url.searchParams.get('v') || (parts[1] === 'shorts' ? (parts[2] || '') : '');
        } catch (error) { return ''; }
    };
    // O player da pagina sabe o que esta realmente tocando; a URL pode estar atrasada.
    const playerVideoID = () => {
        try {
            const player = document.getElementById('movie_player');
            const data = player && player.getVideoData && player.getVideoData();
            return (data && data.video_id) || '';
        } catch (error) { return ''; }
    };
    // No YouTube Music a URL atualiza com atraso; no YouTube o player reporta o anuncio.
    const isMusic = window.location.hostname.startsWith('music.');
    const videoID = () => isMusic
        ? (playerVideoID() || urlVideoID())
        : (urlVideoID() || playerVideoID());
    const isMedia = (target) => target instanceof HTMLMediaElement;

    document.addEventListener('playing', (event) => {
        if (isMedia(event.target)) post({ type: 'playing', videoID: videoID() });
    }, true);
    ['pause', 'ended'].forEach((name) => document.addEventListener(name, (event) => {
        if (isMedia(event.target)) post({ type: 'paused', videoID: videoID() });
    }, true));
    document.addEventListener('enterpictureinpicture', () => post({ type: 'pip', active: true }), true);
    document.addEventListener('leavepictureinpicture', () => post({ type: 'pip', active: false }), true);
    document.addEventListener('webkitpresentationmodechanged', (event) => {
        const target = event.target;
        if (target instanceof HTMLVideoElement) {
            post({ type: 'pip', active: target.webkitPresentationMode === 'picture-in-picture' });
        }
    }, true);
})();
