(() => {
    const unique = '__abFlNG8d4k6PlMHewiCh__';

    const ids = new Map();
    const videos = new WeakMap();

    function getMeta() {
        try {
            const metas = Array.from(document.querySelectorAll('meta'));
            const images = metas.filter(meta => meta.getAttribute('property') == 'og:image');
            const titles = metas.filter(meta => meta.getAttribute('property') == 'og:title');
            const args = ytInitialPlayerConfig && ytInitialPlayerConfig.args || null;
            return {
                image: (images.length > 0 ? images[0].getAttribute('content') : (args && args.iurl)) || null,
                title: (titles.length > 0 ? titles[0].getAttribute('content') : (args && args.title)) || null,
            };
        } catch (e) {
            report('Failed to get meta', e);
            return {image: null, title: null};
        }
    }

    function isFrame() {
        try {
            return window.self !== window.top;
        } catch (e) {
            return true;
        }
    }

    const randomBase = 36;
    const randomRange = Math.pow(randomBase, 10);
    function randomId() {
        const r = Math.random() * randomRange;
        return (randomRange + Math.floor(r)).toString(randomBase).substr(1);
    }

    function report(context, e) {
        window.webkit.messageHandlers.reactionCam.postMessage({
            type: 'error',
            context: context,
            error: e && e.toString() || null,
        });
    }

    function stylePlay(div, rect) {
        div.style.alignItems = 'center';
        div.style.backgroundPosition = '50% 50%';
        div.style.backgroundSize = 'cover';
        div.style.display = 'flex';
        div.style.fontSize = '18px';
        div.style.height = `${rect.height}px`;
        div.style.justifyContent = 'center';
        div.style.left = '0';
        div.style.position = 'absolute';
        div.style.top = '0';
        div.style.width = '100%';
        div.style.zIndex = '9999';
        div.innerHTML = '<span>Tap to play full screen</span>';
        const span = div.childNodes[0];
        span.style.webkitBackdropFilter = 'blur(5px)';
        span.style.background = 'rgba(0, 0, 0, .5)';
        span.style.color = '#fff';
        span.style.height = '100%';
        span.style.lineHeight = `${rect.height}px`;
        span.style.textAlign = 'center';
        span.style.textShadow = '#000 0 0 1px';
        span.style.width = '100%';
        const match = location.search.match(/[?&]v=([^?&]+)/);
        if (match) {
            div.style.backgroundImage = `url(https://i.ytimg.com/vi/${match[1]}/sddefault.jpg)`;
        }
    }

    function restyleAll() {
        const divs = Array.from(document.querySelectorAll(`.${unique}`));
        divs.forEach((div) => {
            const video = ids.get(div.dataset.videoId);
            if (!video) return;
            try {
                const rect = video.getBoundingClientRect();
                stylePlay(div, rect);
            } catch (e) {
                report('Failed to restyle', e);
            }
        });
    }

    function notifyPlay(video) {
        const id = videos.get(video) || randomId();
        const rect = video.getBoundingClientRect();
        if (!ids.has(id)) {
            videos.set(video, id);
            ids.set(id, video);
            try {
                video.style.pointerEvents = 'none';
                video.style.opacity = '0';
                const div = document.createElement('div');
                div.classList.add(unique);
                div.dataset.videoId = id;
                const parent = document.getElementById('player') || video.parentNode;
                parent.appendChild(div);
                div.addEventListener('click', (e) => {
                    e.stopPropagation();
                    notifyPlay(video);
                });
            } catch (e) {
                report('Failed to set up video', e);
            }
        }
        restyleAll();
        const meta = getMeta();
        window.webkit.messageHandlers.reactionCam.postMessage({
            type: 'play',
            id,
            frame: {
                x: rect.left, y: rect.top,
                width: rect.width, height: rect.height,
            },
            image: meta.image,
            src: video.currentSrc || video.src,
            title: meta.title || document.title,
        });
    }

    const fakePlay = new CustomEvent('play');
    HTMLMediaElement.prototype.play = function () {
        this.dispatchEvent(fakePlay);
        setTimeout(() => {
            notifyPlay(this);
            this.pause();
        }, 0);
    };

    if (!isFrame()) {
        document.addEventListener('DOMContentLoaded', e => {
            const meta = getMeta();
            window.webkit.messageHandlers.reactionCam.postMessage({
                type: 'load',
                image: meta.image,
                title: meta.title || document.title,
            });
            const titleElement = document.head.querySelector('title');
            if (!titleElement) return;
            const titleObserver = new MutationObserver(_ => {
                const title = document.title;
                if (title == 'YouTube') return;
                window.webkit.messageHandlers.reactionCam.postMessage({type: 'title', title});
            });
            titleObserver.observe(titleElement, {subtree: true, characterData: true, childList: true});
        });
    }

    document.addEventListener('play', e => {
        if (e === fakePlay) return;
        setTimeout(() => {
            notifyPlay(e.target);
            e.target.pause();
        }, 0);
    }, true);

    window.addEventListener('resize', () => {
        setTimeout(() => {
            restyleAll();
        }, 0);
    });

    window[unique] = {
        event(id, type) {
            if (!ids.has(id)) return;
            const e = (type == 'play' ? fakePlay : new CustomEvent(type, {bubbles: true}));
            ids.get(id).dispatchEvent(e);
        }
    };
})();
