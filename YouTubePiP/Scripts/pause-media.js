// Pausa toda a midia da pagina (o player nativo assumiu ou a outra aba comecou a tocar).
(() => {
    document.querySelectorAll('audio, video').forEach((item) => item.pause());
    return 'paused';
})();
