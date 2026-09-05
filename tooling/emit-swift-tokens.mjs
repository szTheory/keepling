#!/usr/bin/env node
/**
 * D-46: generates the committed Swift design-token output for apps/ios/
 * from packages/design-tokens/tokens.json, the same DTCG semantic token
 * source packages/design-tokens/css.css is generated from.
 *
 * Mirrors tooling/check-contracts.mjs's committed-generated-output
 * precedent and tooling/generate-ios-client.mjs's `--check`-and-diff
 * pattern: `--check` regenerates into memory and diffs against the
 * committed file, exiting non-zero on any difference, rather than trusting
 * a build-tool plugin.
 *
 * Mechanical by design (04-04-PLAN.md Task 2): no token name or hex value
 * is hard-coded here. Every space/layout/motion/color token in
 * tokens.json is emitted generically by iterating its keys. The one
 * closed lookup table this file owns is the four-role Dynamic Type text
 * style mapping (label/body/heading/display -> system text style +
 * weight), which 04-UI-SPEC.md's Typography section fixes as a platform
 * contract, not a value tokens.json carries numerically -- an unrecognized
 * typography role name fails loudly (T-04-04-05's accepted disposition:
 * fail loudly on an unhandled token shape rather than emit a partial
 * file) rather than being silently skipped or guessed at.
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { resolve } from 'node:path'
import process from 'node:process'

const repositoryRoot = resolve(import.meta.dirname, '..')
const tokensPath = resolve(repositoryRoot, 'packages/design-tokens/tokens.json')
const outputPath = resolve(
  repositoryRoot,
  'apps/ios/Sources/Keepling/DesignTokens/GeneratedTokens.swift',
)

const fail = (message) => {
  process.stderr.write(`emit-swift-tokens: ${message}\n`)
  process.exit(1)
}

if (!existsSync(tokensPath)) fail(`missing token source at ${tokensPath}`)

const tokens = JSON.parse(readFileSync(tokensPath, 'utf8'))

// -- helpers ---------------------------------------------------------------

/** "4px" -> 4, "160ms" -> 160. Fails loudly on any other unit/shape. */
const numericValue = (raw, context) => {
  const match = /^(-?\d+(?:\.\d+)?)(px|ms)$/.exec(raw)
  if (!match) fail(`${context}: expected a "<number>px" or "<number>ms" value, got "${raw}"`)
  return Number(match[1])
}

/** "#f7f2e8" -> { r, g, b, hexUpper: "#F7F2E8" }. Fails loudly on non-hex. */
const hexColor = (raw, context) => {
  const match = /^#([0-9a-fA-F]{6})$/.exec(raw)
  if (!match) fail(`${context}: expected a 6-digit hex color, got "${raw}"`)
  const hex = match[1]
  const r = parseInt(hex.slice(0, 2), 16) / 255
  const g = parseInt(hex.slice(2, 4), 16) / 255
  const b = parseInt(hex.slice(4, 6), 16) / 255
  return { r, g, b, hexUpper: `#${hex.toUpperCase()}` }
}

const swiftFloat = (value) => {
  // Swift accepts "4" and "0.16" as Double/CGFloat literals directly; keep
  // integral values unadorned for readability, matching css.css's style.
  return Number.isInteger(value) ? String(value) : String(value)
}

const pascalCase = (key) =>
  key
    .split(/(?=[A-Z])|[-_]/)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join('')

/**
 * A DTCG token key like "2xl" is not a legal bare Swift identifier (it
 * starts with a digit); Swift's backtick-escaping (`` `2xl` ``) makes any
 * token key usable as an identifier without renaming it away from its
 * source name, keeping the emitted name mechanically traceable back to
 * tokens.json.
 */
const swiftIdentifier = (key) => {
  const sanitized = key.replace(/-/g, '_')
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(sanitized) ? sanitized : `\`${sanitized}\``
}

// -- typography: the one closed, UI-SPEC-fixed lookup table ---------------
// 04-UI-SPEC.md § Typography fixes exactly these four roles, weights, and
// nearest system text styles. tokens.json's `typography.*` keys drive
// WHICH roles are emitted; this table supplies HOW each known role maps to
// a Dynamic Type text style, since that mapping is a platform contract,
// not a value with a numeric encoding in the DTCG source.
const TYPOGRAPHY_TEXT_STYLE_MAP = {
  label: { textStyle: 'footnote', weight: 'semibold' },
  body: { textStyle: 'body', weight: 'regular' },
  heading: { textStyle: 'title3', weight: 'semibold' },
  display: { textStyle: 'largeTitle', weight: 'semibold' },
}

// -- build the Swift source -------------------------------------------------

const lines = []
lines.push('// GENERATED FILE -- do not edit by hand.')
lines.push('// Regenerate with: pnpm tokens:swift (node tooling/emit-swift-tokens.mjs)')
lines.push('// Source of truth: packages/design-tokens/tokens.json')
lines.push('import SwiftUI')
lines.push('import UIKit')
lines.push('')
lines.push('/// Mechanically generated from packages/design-tokens/tokens.json (D-46).')
lines.push('/// Never consumed directly by views -- see TokenSemantics.swift for the')
lines.push('/// hand-written, semantically-named accessor layer every view uses.')
lines.push('public enum GeneratedTokens {')

// Space
lines.push('    public enum Space {')
for (const [key, node] of Object.entries(tokens.space ?? {})) {
  const value = numericValue(node.$value, `space.${key}`)
  lines.push(`        public static let ${swiftIdentifier(key)}: CGFloat = ${swiftFloat(value)}`)
}
lines.push('    }')
lines.push('')

// Layout
lines.push('    public enum Layout {')
for (const [key, node] of Object.entries(tokens.layout ?? {})) {
  const value = numericValue(node.$value, `layout.${key}`)
  lines.push(`        public static let ${key}: CGFloat = ${swiftFloat(value)}`)
}
lines.push('    }')
lines.push('')

// Motion
lines.push('    public enum Motion {')
for (const [key, node] of Object.entries(tokens.motion ?? {})) {
  const ms = numericValue(node.$value, `motion.${key}`)
  lines.push(`        public static let ${key}: Double = ${swiftFloat(ms / 1000)} // ${node.$value}`)
}
lines.push('    }')
lines.push('')

// Typography: exactly four roles, mapped to Dynamic Type text styles.
const typographyKeys = Object.keys(tokens.typography ?? {})
if (typographyKeys.length !== 4) {
  fail(
    `expected exactly four typography roles per 04-UI-SPEC.md, found ${typographyKeys.length}: ${typographyKeys.join(', ')}`,
  )
}
lines.push('    public enum Typography {')
for (const key of typographyKeys) {
  const mapping = TYPOGRAPHY_TEXT_STYLE_MAP[key]
  if (!mapping) {
    fail(
      `typography role "${key}" has no entry in TYPOGRAPHY_TEXT_STYLE_MAP -- 04-UI-SPEC.md's Typography section must name its Dynamic Type text style and weight before this emitter can produce it`,
    )
  }
  const baseSize = tokens.typography[key].$value
  lines.push(
    `        /// Base size @ default Dynamic Type: ${baseSize} (scales via Dynamic Type, not a fixed size)`,
  )
  lines.push(
    `        public static let ${key} = SwiftUI.Font.system(.${mapping.textStyle}, design: .default, weight: .${mapping.weight})`,
  )
}
lines.push('    }')
lines.push('')

// Color: light/dark pairs, resolved at runtime (D-47) via a dynamic
// UIColor provider so a live system-appearance change applies to a
// running app rather than being baked in at launch.
const lightColors = tokens.color?.light ?? {}
const darkColors = tokens.color?.dark ?? {}
const colorKeys = Object.keys(lightColors)
const missingDark = colorKeys.filter((key) => !(key in darkColors))
if (missingDark.length > 0) fail(`color tokens missing a dark pair: ${missingDark.join(', ')}`)
const extraDark = Object.keys(darkColors).filter((key) => !(key in lightColors))
if (extraDark.length > 0) fail(`color tokens have a dark value with no light pair: ${extraDark.join(', ')}`)

lines.push('    public enum Color {')
for (const key of colorKeys) {
  const light = hexColor(lightColors[key].$value, `color.light.${key}`)
  const dark = hexColor(darkColors[key].$value, `color.dark.${key}`)
  lines.push(`        /// Light ${light.hexUpper}, Dark ${dark.hexUpper}`)
  lines.push(`        public static let ${key} = SwiftUI.Color(uiColor: UIKit.UIColor { traitCollection in`)
  lines.push(`            switch traitCollection.userInterfaceStyle {`)
  lines.push(`            case .dark:`)
  lines.push(
    `                UIKit.UIColor(red: ${dark.r.toFixed(6)}, green: ${dark.g.toFixed(6)}, blue: ${dark.b.toFixed(6)}, alpha: 1) // ${dark.hexUpper}`,
  )
  lines.push(`            default:`)
  lines.push(
    `                UIKit.UIColor(red: ${light.r.toFixed(6)}, green: ${light.g.toFixed(6)}, blue: ${light.b.toFixed(6)}, alpha: 1) // ${light.hexUpper}`,
  )
  lines.push(`            }`)
  lines.push('        })')
}
lines.push('    }')

lines.push('}')
lines.push('')

const swiftSource = `${lines.join('\n')}`

// -- write or check ----------------------------------------------------------

const checkMode = process.argv.includes('--check')

if (!checkMode) {
  writeFileSync(outputPath, swiftSource)
  process.stdout.write(`emit-swift-tokens: wrote ${outputPath}\n`)
  process.exit(0)
}

if (!existsSync(outputPath)) {
  fail(`--check: committed output missing at ${outputPath} -- run \`node tooling/emit-swift-tokens.mjs\` first`)
}
const committed = readFileSync(outputPath, 'utf8')
if (committed !== swiftSource) {
  fail(
    `--check: committed ${outputPath} differs from tokens.json -- run \`node tooling/emit-swift-tokens.mjs\` and commit the result`,
  )
}
process.stdout.write('emit-swift-tokens --check: committed Swift token output is current\n')
