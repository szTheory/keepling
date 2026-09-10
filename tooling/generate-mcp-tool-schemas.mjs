#!/usr/bin/env node
/**
 * D-12: generates packages/contracts/generated/mcp-tools.schema.json -- a
 * single JSON document mapping each of MCP-02's six tool names to its
 * resolved, self-contained JSON Schema, with every `$ref` inlined so the
 * server does not need a schema resolver at runtime (05-05-PLAN.md Task 1).
 *
 * Mirrors tooling/generate-ios-client.mjs's `--check` idiom (see that
 * file's own header comment): regenerate into a scratch directory and diff
 * against the committed output, exiting non-zero on any difference, rather
 * than trusting an un-diffed codegen step.
 */
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { load } from 'js-yaml'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import process from 'node:process'

const repositoryRoot = resolve(import.meta.dirname, '..')
const contractPath = join(repositoryRoot, 'packages', 'contracts', 'openapi', 'keepling.yaml')
const committedOutputPath = join(repositoryRoot, 'packages', 'contracts', 'generated', 'mcp-tools.schema.json')

const fail = (message) => {
  process.stderr.write(`generate-mcp-tool-schemas: ${message}\n`)
  process.exit(1)
}

// Tool name -> component schema name. Closed to exactly these six (D-11) --
// no MCP tool exists that is not one of these; the twelve command endpoints
// are not mirrored one for one.
const TOOLS = {
  'keepling.capture_task': 'McpCaptureTaskParams',
  'keepling.update_task': 'McpUpdateTaskParams',
  'keepling.complete_task': 'McpCompleteTaskParams',
  'keepling.reopen_task': 'McpReopenTaskParams',
  'keepling.preview_bulk_change': 'McpPreviewBulkChangeParams',
  'keepling.commit_bulk_change': 'McpCommitBulkChangeParams',
}

const REF_PREFIX = '#/components/schemas/'

/**
 * Recursively inline every `$ref` pointing at `#/components/schemas/<name>`
 * into a self-contained schema tree. `seen` guards against infinite
 * recursion on a self- or mutually-referential schema (none of the six
 * tools' schemas are recursive today, but a future contract edit could
 * introduce one, and a silent stack overflow is a worse failure mode than
 * a named error).
 */
const inlineRefs = (node, schemas, seen) => {
  if (Array.isArray(node)) return node.map((item) => inlineRefs(item, schemas, seen))
  if (node === null || typeof node !== 'object') return node

  if (typeof node.$ref === 'string' && node.$ref.startsWith(REF_PREFIX)) {
    const targetName = node.$ref.slice(REF_PREFIX.length)
    if (seen.has(targetName)) {
      fail(`circular $ref detected while inlining schema "${targetName}" -- cannot produce a self-contained document`)
    }
    const target = schemas[targetName]
    if (!target) fail(`$ref points at unknown component schema "${targetName}"`)
    const nextSeen = new Set(seen)
    nextSeen.add(targetName)
    // Any sibling keys beside $ref (OpenAPI allows description overrides,
    // for example) are preserved and layered on top of the resolved target.
    const { $ref, ...siblings } = node
    const resolvedTarget = inlineRefs(target, schemas, nextSeen)
    return { ...resolvedTarget, ...inlineRefs(siblings, schemas, seen) }
  }

  const result = {}
  for (const [key, value] of Object.entries(node)) {
    result[key] = inlineRefs(value, schemas, seen)
  }
  return result
}

const buildSchemas = () => {
  if (!existsSync(contractPath)) fail(`missing OpenAPI contract at ${contractPath}`)
  const contract = load(readFileSync(contractPath, 'utf8'))
  const schemas = contract?.components?.schemas
  if (!schemas || typeof schemas !== 'object') fail('contract has no components.schemas map')

  const output = {}
  for (const [toolName, schemaName] of Object.entries(TOOLS)) {
    const schema = schemas[schemaName]
    if (!schema) fail(`component schema "${schemaName}" for tool "${toolName}" not found in contract`)
    const resolved = inlineRefs(schema, schemas, new Set([schemaName]))
    if (resolved.additionalProperties !== false) {
      fail(`resolved schema for "${toolName}" is not closed (additionalProperties must be false)`)
    }
    output[toolName] = resolved
  }
  return output
}

const writeSchemas = (outputPath) => {
  const output = buildSchemas()
  mkdirSync(join(outputPath, '..'), { recursive: true })
  writeFileSync(outputPath, `${JSON.stringify(output, null, 2)}\n`, 'utf8')
}

const checkMode = process.argv.includes('--check')

if (!checkMode) {
  writeSchemas(committedOutputPath)
  process.stdout.write(`generate-mcp-tool-schemas: wrote ${Object.keys(TOOLS).length} tool schemas to ${committedOutputPath}\n`)
  process.exit(0)
}

const scratchDir = mkdtempSync(join(tmpdir(), 'keepling-mcp-tool-schemas-'))
try {
  const scratchOutputPath = join(scratchDir, 'mcp-tools.schema.json')
  writeSchemas(scratchOutputPath)

  if (!existsSync(committedOutputPath)) {
    fail(`committed output missing at ${committedOutputPath} -- run \`node tooling/generate-mcp-tool-schemas.mjs\` first`)
  }
  const committed = readFileSync(committedOutputPath, 'utf8')
  const fresh = readFileSync(scratchOutputPath, 'utf8')
  if (committed !== fresh) {
    fail('committed packages/contracts/generated/mcp-tools.schema.json differs from a fresh generation')
  }
  process.stdout.write('generate-mcp-tool-schemas --check: committed schema is current\n')
} finally {
  rmSync(scratchDir, { recursive: true, force: true })
}
