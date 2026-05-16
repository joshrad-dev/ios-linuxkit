import { DEFAULT_THEME, init, Terminal, FitAddon } from './ghostty-web.js';

// Shorthand for JS -> native IPC. Keep the same message-handler names used by
// Terminal.m / TerminalView.m so the Objective-C side does not need a new bridge.
const native = new Proxy({}, {
    get(_obj, prop) {
        return (...args) => {
            if (!window.webkit?.messageHandlers?.[prop])
                return;
            let body;
            if (args.length === 0)
                body = null;
            else if (args.length === 1)
                body = args[0];
            else
                body = args;
            window.webkit.messageHandlers[prop].postMessage(body);
        };
    },
});

const ANSI_COLOR_NAMES = [
    'black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white',
    'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue',
    'brightMagenta', 'brightCyan', 'brightWhite',
];

const cursorShapeMap = {
    BLOCK: 'block',
    BEAM: 'bar',
    UNDERLINE: 'underline',
};

let term;
let fitAddon;
let lastApplicationCursor;
let lastScrollHeight;
let lastScrollTop;
let pendingStyle = null;

window.exports = {
    write,
    getSize,
    copy,
    clearScrollback,
    setFocused,
    scrollToBottom,
    newScrollTop,
    updateStyle,
    getCharacterSize,
    setUserGesture,
    setAccessibilityEnabled,
};

window.addEventListener('load', async () => {
    try {
        await init();

        term = new Terminal({
            cols: 80,
            rows: 24,
            cursorBlink: true,
            fontSize: 15,
            fontFamily: 'Menlo, Monaco, "Courier New", monospace',
            scrollback: 10000,
            smoothScrollDuration: 0,
            scrollbarWidth: 0,
            theme: {
                background: '#000000',
                foreground: '#ffffff',
                cursor: '#ffffff',
            },
            onLinkClick: (url) => {
                native.openLink(url);
                return true;
            },
        });

        fitAddon = new FitAddon();
        term.loadAddon(fitAddon);

        term.onData((data) => native.sendInput(data));
        term.onResize(() => {
            syncWindowSize();
            syncScroll();
        });
        term.onScroll(() => syncScroll());
        term.onRender(() => {
            syncApplicationCursor();
            syncScroll();
        });

        term.open(document.getElementById('terminal'));
        fit();
        if (pendingStyle)
            applyStyle(pendingStyle);

        if (typeof ResizeObserver === 'function') {
            const resizeObserver = new ResizeObserver(() => {
                fit();
                syncWindowSize();
                syncScroll();
            });
            resizeObserver.observe(document.getElementById('terminal'));
        }
        window.addEventListener('resize', () => {
            fit();
            syncWindowSize();
            syncScroll();
        });

        syncApplicationCursor();
        syncWindowSize();
        syncScroll(true);
        native.load();
        native.syncFocus();
    } catch (error) {
        native.log(`ghostty terminal init failed: ${error?.stack || error}`);
        throw error;
    }
});

function fit() {
    if (!fitAddon || !term)
        return;
    fitAddon.fit();
}

function stringToBytes(data) {
    const bytes = new Uint8Array(data.length);
    for (let i = 0; i < data.length; i++)
        bytes[i] = data.charCodeAt(i) & 0xff;
    return bytes;
}

function write(data) {
    if (!term)
        return;
    if (typeof data === 'string')
        term.write(stringToBytes(data));
    else
        term.write(data);
    syncApplicationCursor();
    syncScroll();
}

function getSize() {
    if (!term)
        return [80, 24];
    return [term.cols, term.rows];
}

function copy() {
    term?.copySelection();
}

function clearScrollback() {
    // ghostty-web does not expose hterm's exact clearScrollback primitive yet.
    // Match the user's visible expectation: clear the screen and return to the
    // bottom of history.
    term?.clear();
    term?.scrollToBottom();
    syncScroll(true);
}

function setFocused(focus) {
    if (!term)
        return;
    if (focus)
        term.focus();
    else
        term.blur();
}

function scrollToBottom() {
    term?.scrollToBottom();
    syncScroll(true);
}

function newScrollTop(y) {
    if (!term)
        return;
    const charHeight = getCharacterSize()[1] || 1;
    const scrollback = term.getScrollbackLength?.() || 0;
    const lineFromTop = Math.max(0, Math.round(y / charHeight));
    const viewportFromBottom = Math.max(0, Math.min(scrollback, scrollback - lineFromTop));
    term.scrollToLine(viewportFromBottom);
    syncScroll(true);
}

function updateStyle(style) {
    pendingStyle = style;
    if (!term)
        return;
    applyStyle(style);
}

function applyStyle({ foregroundColor, backgroundColor, fontFamily, fontSize, colorPaletteOverrides, blinkCursor, cursorShape }) {
    const theme = {
        ...DEFAULT_THEME,
        foreground: foregroundColor,
        background: backgroundColor,
        cursor: foregroundColor,
    };
    if (Array.isArray(colorPaletteOverrides)) {
        for (let i = 0; i < Math.min(colorPaletteOverrides.length, ANSI_COLOR_NAMES.length); i++) {
            if (colorPaletteOverrides[i])
                theme[ANSI_COLOR_NAMES[i]] = colorPaletteOverrides[i];
        }
    }

    term.options.theme = theme;
    term.options.fontFamily = fontFamily;
    term.options.fontSize = fontSize;
    term.options.cursorBlink = !!blinkCursor;
    term.options.cursorStyle = cursorShapeMap[cursorShape] || 'block';

    // Font/style changes alter cell metrics; refit and publish the new PTY size.
    if (document.fonts?.load)
        document.fonts.load(`${fontSize}px ${fontFamily}`).catch(() => {});
    fit();
    syncWindowSize();
    syncScroll(true);
}

function getCharacterSize() {
    const renderer = term?.renderer;
    if (!renderer)
        return [8, 16];
    if (renderer.getMetrics) {
        const metrics = renderer.getMetrics();
        return [metrics.width, metrics.height];
    }
    return [renderer.charWidth || 8, renderer.charHeight || 16];
}

function setUserGesture() {
    // hterm-specific accessibility hook; no equivalent is required for ghostty-web.
}

function setAccessibilityEnabled(_enabled) {
    // hterm exposed a screen-reader toggle. Ghostty-Web does not currently need
    // one, but Terminal.m still calls through this bridge when views attach or
    // detach. Keep the endpoint explicit so those calls do not throw in WKWebView.
}

function syncWindowSize() {
    native.resize();
}

function syncApplicationCursor() {
    const applicationCursor = !!term?.wasmTerm?.getMode?.(1, false);
    if (applicationCursor !== lastApplicationCursor) {
        lastApplicationCursor = applicationCursor;
        native.propUpdate('applicationCursor', applicationCursor);
    }
}

function syncScroll(force = false) {
    if (!term)
        return;
    const charHeight = getCharacterSize()[1] || 1;
    const scrollback = term.getScrollbackLength?.() || 0;
    const viewportY = term.getViewportY?.() || 0;
    const scrollHeight = (scrollback + term.rows) * charHeight;
    const scrollTop = Math.max(0, (scrollback - viewportY) * charHeight);

    if (force || scrollHeight !== lastScrollHeight) {
        lastScrollHeight = scrollHeight;
        native.newScrollHeight(scrollHeight);
    }
    if (force || scrollTop !== lastScrollTop) {
        lastScrollTop = scrollTop;
        native.newScrollTop(scrollTop);
    }
}
