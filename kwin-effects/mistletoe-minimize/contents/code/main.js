// Mistletoe Minimize.
//
// A minimized window folds down into the middle of the strip, where the arc
// shows the active app, shrinking and fading as it goes; restoring it unfolds
// it from the same spot. KWin's own Squash effect needs a task manager icon
// to aim at, which the Mistletoe strip doesn't publish, so without this
// windows simply vanish. (Both effects are in the "minimize" category, so
// enabling this one turns Squash off.)
"use strict";

const fold = {
    duration: animationTime(280),
    // How small the window gets, and how far above the screen's bottom edge
    // its center lands (the middle of the 44px strip).
    scale: 0.06,
    lift: 22,

    loadConfig: function () {
        fold.duration = animationTime(280);
    },

    // Where a window folds to: bottom center of the screen it is on.
    offset: function (window) {
        const rect = window.geometry;
        const screen = (window.screen && window.screen.geometry) || effects.virtualScreenGeometry;
        return {
            x: screen.x + screen.width / 2 - (rect.x + rect.width / 2),
            y: screen.y + screen.height - fold.lift - (rect.y + rect.height / 2)
        };
    },

    minimized: function (window) {
        if (effects.hasActiveFullScreenEffect) {
            return;
        }
        if (window.unfoldAnimation) {
            if (redirect(window.unfoldAnimation, Effect.Backward)) {
                return;
            }
            cancel(window.unfoldAnimation);
            delete window.unfoldAnimation;
        }
        if (window.foldAnimation) {
            if (redirect(window.foldAnimation, Effect.Forward)) {
                return;
            }
            cancel(window.foldAnimation);
        }
        const to = fold.offset(window);
        window.foldAnimation = animate({
            window: window,
            curve: QEasingCurve.InCubic,
            duration: fold.duration,
            keepAlive: false,
            animations: [
                { type: Effect.Scale, from: 1.0, to: fold.scale },
                { type: Effect.Translation, from: { value1: 0, value2: 0 }, to: { value1: to.x, value2: to.y } },
                // Stay solid for most of the way, then fade into the strip.
                { type: Effect.Opacity, curve: QEasingCurve.InQuart, from: 1.0, to: 0.0 }
            ]
        });
    },

    unminimized: function (window) {
        if (effects.hasActiveFullScreenEffect) {
            return;
        }
        if (window.foldAnimation) {
            if (redirect(window.foldAnimation, Effect.Backward)) {
                return;
            }
            cancel(window.foldAnimation);
            delete window.foldAnimation;
        }
        if (window.unfoldAnimation) {
            if (redirect(window.unfoldAnimation, Effect.Forward)) {
                return;
            }
            cancel(window.unfoldAnimation);
        }
        const from = fold.offset(window);
        window.unfoldAnimation = animate({
            window: window,
            curve: QEasingCurve.OutCubic,
            duration: fold.duration,
            keepAlive: false,
            animations: [
                { type: Effect.Scale, from: fold.scale, to: 1.0 },
                { type: Effect.Translation, from: { value1: from.x, value2: from.y }, to: { value1: 0, value2: 0 } },
                { type: Effect.Opacity, curve: QEasingCurve.OutQuart, from: 0.0, to: 1.0 }
            ]
        });
    },

    watch: function (window) {
        window.minimizedChanged.connect(() => {
            if (window.minimized) {
                fold.minimized(window);
            } else {
                fold.unminimized(window);
            }
        });
    },

    init: function () {
        effect.configChanged.connect(fold.loadConfig);
        effects.windowAdded.connect(fold.watch);
        for (const window of effects.stackingOrder) {
            fold.watch(window);
        }
    }
};

fold.init();
