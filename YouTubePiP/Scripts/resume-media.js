// Volta a tocar na pagina quando o player nativo nao conseguiu abrir o conteudo.
(() => {
    const media = Array.from(document.querySelectorAll('audio, video'))
        .find((item) => item.readyState > 0);
    if (!media) return 'missing';
    media.play().catch(() => {});
    return 'playing';
})();
