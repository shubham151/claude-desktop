// Linux shim for claude-native bindings (replaces the macOS .node module).
// Unknown calls no-op and warn rather than throw.

interface WindowState {
  isMaximized: boolean
  isMinimized: boolean
  isFullScreen: boolean
}

interface NativeApi {
  getWindowState(): WindowState
  setWindowState(state: Partial<WindowState>): void
  getSystemIdleTime(): number
  getAutoLaunchEnabled(): boolean
  setAutoLaunchEnabled(enabled: boolean): void
  setBadgeCount(count: number): void
  getBadgeCount(): number
  isAccessibilityEnabled(): boolean
  requestAccessibility(): boolean
  KeyboardKey: Record<string, string>
  [key: string]: unknown
}

const api: NativeApi = {
  getWindowState: () => ({ isMaximized: false, isMinimized: false, isFullScreen: false }),
  setWindowState: () => {},
  getSystemIdleTime: () => 0,
  getAutoLaunchEnabled: () => false,
  setAutoLaunchEnabled: () => {},
  setBadgeCount: () => {},
  getBadgeCount: () => 0,
  isAccessibilityEnabled: () => false,
  requestAccessibility: () => false,
  KeyboardKey: {
    Backspace: 'Backspace',
    Tab: 'Tab',
    Return: 'Return',
    Enter: 'Enter',
    Shift: 'Shift',
    Control: 'Control',
    Alt: 'Alt',
    Meta: 'Meta',
    CapsLock: 'CapsLock',
    Escape: 'Escape',
    Space: 'Space',
    PageUp: 'PageUp',
    PageDown: 'PageDown',
    End: 'End',
    Home: 'Home',
    ArrowLeft: 'ArrowLeft',
    ArrowUp: 'ArrowUp',
    ArrowRight: 'ArrowRight',
    ArrowDown: 'ArrowDown',
    Insert: 'Insert',
    Delete: 'Delete',
    Comma: ',',
    Period: '.',
    Slash: '/',
    Semicolon: ';',
    Quote: "'",
    BracketLeft: '[',
    BracketRight: ']',
    Backslash: '\\',
    Minus: '-',
    Equal: '=',
  },
}

for (let i = 0; i < 26; i++) {
  const c = String.fromCharCode(65 + i)
  api.KeyboardKey[c] = c
}
for (let i = 0; i <= 9; i++) {
  api.KeyboardKey[`Digit${i}`] = String(i)
}
for (let i = 1; i <= 24; i++) {
  api.KeyboardKey[`F${i}`] = `F${i}`
}

module.exports = new Proxy(api, {
  get(target, prop) {
    if (prop in target) return (target as unknown as Record<string | symbol, unknown>)[prop]
    if (typeof prop === 'symbol') return undefined
    console.warn(`[claude-native-bindings] unknown export accessed: ${String(prop)}`)
    return () => {}
  },
})
