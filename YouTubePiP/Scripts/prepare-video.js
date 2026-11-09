// YouTube: deixa os <video> prontos para tocar inline. Injetado ao fim de cada pagina.
(() => {
    if (window.__ytpipPrepareVideo) return;
    window.__ytpipPrepareVideo = true;

    const prepare = () => {
        document.querySelectorAll('video').forEach((video) => {
            video.setAttribute('playsinline', '');
            video.setAttribute('webkit-playsinline', '');
        });
    };

    // O YouTube altera o DOM o tempo todo; agrupa as mudancas em no maximo uma passada por quadro.
    let scheduled = false;
    const schedule = () => {
        if (scheduled) return;
        scheduled = true;
        requestAnimationFrame(() => {
            scheduled = false;
            prepare();
        });
    };

    prepare();
    new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
})();
