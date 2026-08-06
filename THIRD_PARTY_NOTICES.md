# Third-party notices

## SwiftTerm

AgenTM5N uses SwiftTerm 1.11.0 as its embedded VT100/Xterm terminal emulator
and PTY frontend. AgenTM5N uses the CoreText renderer and does not enable
SwiftTerm's optional Metal renderer.

- Project: SwiftTerm
- Copyright: Miguel de Icaza and contributors
- License: MIT
- Repository: `https://github.com/migueldeicaza/SwiftTerm`

AgenTM5N does not modify SwiftTerm. The dependency source and license are
resolved by Swift Package Manager.
