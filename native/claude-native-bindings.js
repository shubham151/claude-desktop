// Linux shim for claude-native bindings (replaces the macOS .node module).
// All unknown calls no-op and warn rather than throw.

const api = {}

api.getWindowState = () => ({ isMaximized: false, isMinimized: false, isFullScreen: false })
api.setWindowState = () => {}
api.getSystemIdleTime = () => 0
api.getAutoLaunchEnabled = () => false
api.setAutoLaunchEnabled = () => {}
api.setBadgeCount = () => {}
api.getBadgeCount = () => 0
api.isAccessibilityEnabled = () => false
api.requestAccessibility = () => false

api.KeyboardKey = {
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
    if (prop in target) return target[prop]
    if (typeof prop === 'symbol') return undefined
    console.warn(`[claude-native-bindings] unknown export accessed: ${String(prop)}`)
    return () => {}
  },
})
