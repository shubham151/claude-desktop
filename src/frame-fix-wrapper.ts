// Loaded as the app's main entry. Patches electron.BrowserWindow so that
// windows constructed by the original app get proper Linux frame/decorations,
// then delegates to the original main module recorded in package.json.

import Module = require('module')
import * as path from 'path'

type ElectronModule = {
  BrowserWindow: new (opts?: Record<string, unknown>) => unknown
  app: { whenReady: () => Promise<void> }
  globalShortcut: { register: (accel: string, cb: () => void) => boolean }
}

const originalLoad = (Module as unknown as { _load: Function })._load
let patched = false

;(Module as unknown as { _load: Function })._load = function (
  request: string,
  parent: unknown,
  isMain: boolean,
): unknown {
  const result = originalLoad.apply(this, arguments as unknown as IArguments)
  if (request === 'electron' && !patched && result && (result as ElectronModule).BrowserWindow) {
    patched = true
    const electron = result as ElectronModule
    const OriginalBW = electron.BrowserWindow as unknown as new (
      opts?: Record<string, unknown>,
    ) => unknown

    function PatchedBW(opts: Record<string, unknown> = {}): unknown {
      const patchedOpts: Record<string, unknown> = {
        ...opts,
        frame: opts.frame !== undefined ? opts.frame : true,
        titleBarStyle: 'default',
      }
      delete patchedOpts.trafficLightPosition
      delete patchedOpts.vibrancy
      delete patchedOpts.visualEffectState
      return Reflect.construct(OriginalBW, [patchedOpts], PatchedBW as unknown as Function)
    }
    Object.setPrototypeOf(PatchedBW.prototype, OriginalBW.prototype)
    Object.setPrototypeOf(PatchedBW, OriginalBW)

    try {
      Object.defineProperty(electron, 'BrowserWindow', {
        value: PatchedBW,
        writable: true,
        configurable: true,
      })
    } catch (e) {
      console.warn('[frame-fix-wrapper] failed to replace BrowserWindow:', e)
    }

    try {
      const { app, globalShortcut } = electron
      app.whenReady().then(() => {
        try {
          globalShortcut.register('Control+Alt+Space', () => {
            const BW = OriginalBW as unknown as { getAllWindows: () => Array<{
              isVisible: () => boolean
              isFocused: () => boolean
              hide: () => void
              show: () => void
              focus: () => void
            }> }
            const wins = BW.getAllWindows()
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

const pkg = require('./package.json') as { _originalMain?: string; main?: string }
const originalMain = pkg._originalMain || pkg.main || 'index.js'
require(path.join(__dirname, originalMain))
