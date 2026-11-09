// YouTube Music: esconde o <video> (o app toca so o audio). Injetado ao fim de cada pagina.
(() => {
    if (window.__ytpipAudioOnly) return;
    window.__ytpipAudioOnly = true;

    const hide = () => {
        document.querySelectorAll('video').forEach((video) => {
            video.style.opacity = '0';
            video.style.pointerEvents = 'none';
            video.style.position = 'fixed';
            video.style.width = '1px';
            video.style.height = '1px';
            video.style.left = '-10px';
            video.style.top = '-10px';
        });
    };

    // Agrupa as mudancas do DOM em no maximo uma passada por quadro.
    let scheduled = false;
    const schedule = () => {
        if (scheduled) return;
        scheduled = true;
        requestAnimationFrame(() => {
            scheduled = false;
            hide();
        });
    };

    hide();
    new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
})();
