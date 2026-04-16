// Loaded as the app's main entry. Patches electron.BrowserWindow so that
// windows constructed by the original app get proper Linux frame/decorations,
// then delegates to the original main module recorded in package.json.

const Module = require('module')
const path = require('path')

const originalLoad = Module._load
let patched = false

Module._load = function (request, parent, isMain) {
  const result = originalLoad.apply(this, arguments)
  if (request === 'electron' && !patched && result && result.BrowserWindow) {
    patched = true
    const OriginalBW = result.BrowserWindow

    function PatchedBW(opts = {}) {
      const patchedOpts = {
        ...opts,
        frame: opts.frame !== undefined ? opts.frame : true,
        titleBarStyle: 'default',
      }
      // Drop macOS-only options that break on Linux
      delete patchedOpts.trafficLightPosition
      delete patchedOpts.vibrancy
      delete patchedOpts.visualEffectState

      return Reflect.construct(OriginalBW, [patchedOpts], PatchedBW)
    }
    Object.setPrototypeOf(PatchedBW.prototype, OriginalBW.prototype)
    Object.setPrototypeOf(PatchedBW, OriginalBW)

    // Preserve static methods (getAllWindows, fromWebContents, etc.) via prototype chain above.
    try {
      Object.defineProperty(result, 'BrowserWindow', {
        value: PatchedBW,
        writable: true,
        configurable: true,
      })
    } catch (e) {
      console.warn('[frame-fix-wrapper] failed to replace BrowserWindow:', e)
    }

    // Register global hotkey once app is ready
    try {
      const { app, globalShortcut } = result
      app.whenReady().then(() => {
        try {
          globalShortcut.register('Control+Alt+Space', () => {
            const wins = OriginalBW.getAllWindows()
            if (!wins.length) return
            const w = wins[0]
            if (w.isVisible() && w.isFocused()) w.hide()
            else { w.show(); w.focus() }
          })
        } catch (e) {
          console.warn('[frame-fix-wrapper] globalShortcut failed:', e)
        }
      })
    } catch (e) {
      console.warn('[frame-fix-wrapper] app hook failed:', e)
    }
  }
  return result
}

const pkg = require('./package.json')
const originalMain = pkg._originalMain || 'index.js'
require(path.join(__dirname, originalMain))
