/**
 * design-tokens: proves the committed Swift design-token output
 * (apps/ios/Sources/Keepling/DesignTokens/GeneratedTokens.swift) is
 * current relative to packages/design-tokens/tokens.json, via
 * tooling/emit-swift-tokens.mjs's own `--check` diff (04-04-PLAN.md
 * Task 2). Unlike the other iOS lanes, this one runs a Node script, not
 * xcodebuild -- there is no XCTest case count to parse, so `parse`
 * reports exactly one case on a clean `--check` exit and throws (a hard
 * lane failure, never a silent zero) on any diff or emitter error.
 */
export default function designTokensLane({ repositoryRoot }) {
  return {
    command: 'node',
    args: ['tooling/emit-swift-tokens.mjs', '--check'],
    cwd: repositoryRoot,
    name: 'design-tokens',
    parse: (stdout, stderr, status) => {
      if (status !== 0) {
        throw new Error(`emit-swift-tokens --check failed: ${stderr.trim() || stdout.trim()}`)
      }
      if (!/committed Swift token output is current/.test(stdout)) {
        throw new Error(`unexpected --check output: ${stdout.trim()}`)
      }
      return 1
    },
    trackedInputPaths: [
      'packages/design-tokens/tokens.json',
      'tooling/emit-swift-tokens.mjs',
      'apps/ios/Sources/Keepling/DesignTokens/GeneratedTokens.swift',
      'apps/ios/Sources/Keepling/DesignTokens/TokenSemantics.swift',
    ],
  }
}
