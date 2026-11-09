// Avaliado sob demanda. Retorna um JSON com o que a pagina esta tocando (lido por PageMediaParser).
(() => {
    const elements = Array.from(document.querySelectorAll('audio, video'));
    const activeElement = elements.find((item) => !item.paused && item.readyState > 0)
        || elements.find((item) => item.readyState > 0)
        || elements[0]
        || null;

    const describe = (item, index) => ({
        index,
        type: item.tagName.toLowerCase(),
        currentSrc: item.currentSrc || '',
        src: item.getAttribute('src') || '',
        paused: item.paused,
        muted: item.muted,
        readyState: item.readyState,
        networkState: item.networkState,
        currentTime: Number.isFinite(item.currentTime) ? Number(item.currentTime.toFixed(3)) : null,
        duration: Number.isFinite(item.duration) ? Number(item.duration.toFixed(3)) : null
    });

    const cleanText = (value) => (value || '').replace(/\s+/g, ' ').trim();
    const textFrom = (root, selectors) => {
        for (const selector of selectors) {
            const element = root && root.querySelector(selector);
            const value = cleanText(element && (element.textContent || element.getAttribute('title')));
            if (value) return value;
        }
        return '';
    };
    const imageFrom = (root) => {
        const image = root && root.querySelector('img');
        return image ? (image.currentSrc || image.src || '') : '';
    };
    const videoIDFromURL = (value) => {
        try {
            return new URL(value, window.location.href).searchParams.get('v') || '';
        } catch (error) {
            return '';
        }
    };

    const page = new URL(window.location.href);
    const isMusic = page.hostname.startsWith('music.');
    const playerBar = document.querySelector('ytmusic-player-bar');
    const shortsMatch = page.pathname.match(/^\/shorts\/([\w-]{6,})/);
    const urlVideoID = page.searchParams.get('v') || (shortsMatch ? shortsMatch[1] : '');

    // Estado real do player da pagina (a URL e a barra podem estar atrasadas no YouTube Music).
    const player = document.getElementById('movie_player');
    const call = (name) => {
        try { return player && typeof player[name] === 'function' ? player[name]() : null; } catch (error) { return null; }
    };
    const playerData = call('getVideoData') || {};
    const playerVideoID = playerData.video_id || '';
    const playerTime = call('getCurrentTime');
    const currentVideoID = isMusic ? (playerVideoID || urlVideoID) : (urlVideoID || playerVideoID);
    const useplayerData = playerVideoID && playerVideoID === currentVideoID;

    const metadata = {
        videoID: currentVideoID,
        playlistID: (isMusic && call('getPlaylistId')) || page.searchParams.get('list') || '',
        title: (useplayerData && cleanText(playerData.title))
            || textFrom(playerBar, ['.title', '.song-title', 'yt-formatted-string.title'])
            || cleanText(document.title.replace(/\s*-\s*YouTube( Music)?\s*$/, '')),
        artist: (useplayerData && cleanText(playerData.author))
            || textFrom(playerBar, ['.byline', '.subtitle', '.secondary-flex-columns']),
        artworkURL: useplayerData
            ? `https://i.ytimg.com/vi/${currentVideoID}/hqdefault.jpg`
            : imageFrom(playerBar),
        currentTime: (useplayerData && Number.isFinite(playerTime)) ? playerTime : null
    };

    const queueRoot = document.querySelector('ytmusic-player-queue')
        || document.querySelector('ytmusic-player-page #side-panel')
        || document.querySelector('#queue');
    const queueElements = queueRoot
        ? Array.from(queueRoot.querySelectorAll('ytmusic-player-queue-item, ytmusic-responsive-list-item-renderer'))
        : [];
    const queueItems = [];
    const seenVideoIDs = new Set();

    // Os componentes da fila guardam os dados da faixa em `item.data` (o link nao tem mais o ID).
    const runsText = (value) => (value && (value.simpleText || (value.runs || []).map((run) => run.text).join(''))) || '';
    const seconds = (text) => {
        const parts = (text || '').split(':').map(Number);
        return parts.length > 1 && parts.every(Number.isFinite) ? parts.reduce((total, part) => total * 60 + part, 0) : null;
    };

    for (const item of queueElements) {
        const data = item.data || {};
        const anchor = item.querySelector('a[href*="watch?v="]');
        const videoID = data.videoId || (anchor ? videoIDFromURL(anchor.href || anchor.getAttribute('href')) : '');
        if (!videoID || seenVideoIDs.has(videoID)) continue;
        seenVideoIDs.add(videoID);
        const thumbnails = (data.thumbnail && data.thumbnail.thumbnails) || [];
        queueItems.push({
            videoID,
            title: runsText(data.title)
                || textFrom(item, ['.song-title', '.title', 'yt-formatted-string.title', 'a[href*="watch?v="]']),
            artist: runsText(data.shortBylineText)
                || textFrom(item, ['.byline', '.subtitle', '.secondary-flex-columns']),
            artworkURL: thumbnails.length ? thumbnails[thumbnails.length - 1].url : imageFrom(item),
            duration: seconds(runsText(data.lengthText))
        });
    }

    if (currentVideoID && !seenVideoIDs.has(currentVideoID)) {
        queueItems.unshift({
            videoID: currentVideoID,
            title: metadata.title,
            artist: metadata.artist,
            artworkURL: metadata.artworkURL
        });
    }

    const resourceURLs = performance.getEntriesByType('resource')
        .map((entry) => entry.name)
        .filter((url) => {
            const value = url.toLowerCase();
            return value.includes('googlevideo.com')
                || value.includes('/videoplayback')
                || value.includes('mime=audio')
                || value.includes('mime%3daudio');
        })
        .slice(-30);

    return JSON.stringify({
        capturedAt: new Date().toISOString(),
        pageURL: window.location.href,
        activeElement: activeElement ? describe(activeElement, elements.indexOf(activeElement)) : null,
        mediaElements: elements.map(describe),
        metadata,
        queueItems,
        resourceURLs
    });
})();
