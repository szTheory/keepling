import { readFileSync } from 'node:fs'

import { describe, expect, it } from 'vitest'

import {
  buildOutboundCommand,
  outboundCommandPath,
  type OutboundBasis,
  type OutboundIntent,
} from '../../main/application/outbound-commands.ts'

/**
 * O-41. These assertions are made against the CHECKED-IN CONTRACT, not
 * against a fixture and not against a hand-copied list of field names.
 *
 * That distinction is the whole point. 03-21 found that the desktop's
 * durable capture bytes had omitted the contract-required `version` and
 * that no test caught it, because the in-process fixture modelling the
 * server sent a DIFFERENT shape than the shipped client -- so it did not
 * even fake the client faithfully. A body a real server will refuse must
 * never reach the outbox: an unpushable command sits there forever,
 * reported as "Saved on this Mac", with nothing able to settle it.
 *
 * The OpenAPI document is parsed here with a deliberately small reader
 * rather than a YAML dependency: the only things needed are one enum and,
 * per schema, its `required` list and its property names.
 */
const contractSource = readFileSync(
  new URL('../../../../packages/contracts/openapi/keepling.yaml', import.meta.url),
  'utf8',
)

const contractLines = contractSource.split('\n')

/** The indented block belonging to `    <name>:` under `components.schemas`. */
const schemaBlock = (name: string): string[] => {
  const start = contractLines.findIndex((line) => line === `    ${name}:`)
  if (start === -1) throw new Error(`contract schema ${name} not found`)
  let end = start + 1
  while (end < contractLines.length && (contractLines[end]!.startsWith('      ') || contractLines[end]!.trim() === '')) {
    end += 1
  }
  return contractLines.slice(start + 1, end)
}

/** `required:` entries of a schema, as declared by the contract. */
const requiredFields = (name: string): string[] => {
  const block = schemaBlock(name)
  const start = block.findIndex((line) => line.trim() === 'required:')
  if (start === -1) throw new Error(`contract schema ${name} declares no required fields`)
  const fields: string[] = []
  for (const line of block.slice(start + 1)) {
    const match = /^ {8}- (\S+)$/.exec(line)
    if (!match) break
    fields.push(match[1]!)
  }
  return fields
}

/** Top-level `properties:` keys of a schema. */
const propertyNames = (name: string): string[] => {
  const block = schemaBlock(name)
  const start = block.findIndex((line) => line.trim() === 'properties:')
  if (start === -1) throw new Error(`contract schema ${name} declares no properties`)
  const names: string[] = []
  for (const line of block.slice(start + 1)) {
    const match = /^ {8}(\w+):$/.exec(line)
    if (match) names.push(match[1]!)
  }
  return names
}

const durableCommandTypes = (() => {
  const block = schemaBlock('DurableCommandType')
  const start = block.findIndex((line) => line.trim() === 'enum:')
  return block.slice(start + 1).flatMap((line) => {
    const match = /^ {8}- (\S+)$/.exec(line)
    return match ? [match[1]!] : []
  })
})()

const publishedPaths = contractLines.flatMap((line) => {
  const match = /^ {2}(\/commands\/[a-z-]+):$/.exec(line)
  return match ? [match[1]!] : []
})

const basis: OutboundBasis = {
  baseNotes: 'the notes the server last confirmed',
  basePlannedOn: null,
  baseTitle: 'Book the ferry',
  expectedRevision: 4,
}

const TASK_ID = '11111111-2222-3333-4444-555555555555'
const MUTATION_ID = '99999999-8888-7777-6666-555555555555'

const cases: Array<{ intent: OutboundIntent; schema: string; type: string }> = [
  {
    intent: { kind: 'edit', notes: 'mine', taskId: TASK_ID, title: 'Book the ferry to Mull' },
    schema: 'EditTaskCommand',
    type: 'edit_task',
  },
  { intent: { kind: 'lifecycle', lifecycle: 'complete', taskId: TASK_ID }, schema: 'TaskLifecycleCommand', type: 'complete_task' },
  { intent: { kind: 'lifecycle', lifecycle: 'reopen', taskId: TASK_ID }, schema: 'TaskLifecycleCommand', type: 'reopen_task' },
  { intent: { kind: 'lifecycle', lifecycle: 'trash', taskId: TASK_ID }, schema: 'TaskLifecycleCommand', type: 'trash_task' },
  { intent: { kind: 'lifecycle', lifecycle: 'restore', taskId: TASK_ID }, schema: 'TaskLifecycleCommand', type: 'restore_task' },
  { intent: { kind: 'move_today', planned: true, taskId: TASK_ID }, schema: 'PlanForTodayRequest', type: 'plan_for_today' },
  { intent: { kind: 'move_today', planned: false, taskId: TASK_ID }, schema: 'PlanForTodayRequest', type: 'unplan_task' },
]

describe('outbound command bytes (O-41)', () => {
  it.each(cases)('$type carries exactly the fields $schema requires', ({ intent, schema, type }) => {
    const command = buildOutboundCommand(intent, basis, MUTATION_ID)
    const body = JSON.parse(command.commandBytes) as Record<string, unknown>

    expect(command.type).toBe(type)
    expect(body.type).toBe(type)
    expect(body.version).toBe(1)
    expect(body.mutation_id).toBe(MUTATION_ID)
    expect(body.task_id).toBe(TASK_ID)

    // Every required field is present -- this is the `version` omission of
    // O-34 made structurally impossible to repeat.
    for (const field of requiredFields(schema)) expect(Object.keys(body)).toContain(field)
    // ...and nothing beyond what the schema publishes. The server decoders
    // compare the exact key set and answer 400 `invalid_command` on any
    // extra key, so a superset is as fatal as a subset.
    for (const key of Object.keys(body)) expect(propertyNames(schema)).toContain(key)
  })

  it.each(cases)('$type is a type the contract publishes, at a path the contract publishes', ({ type }) => {
    expect(durableCommandTypes).toContain(type)
    expect(publishedPaths).toContain(outboundCommandPath(type as never))
  })

  it('sends matching touched-field and base-value key sets for an edit', () => {
    const command = buildOutboundCommand(
      { kind: 'edit', notes: 'mine', taskId: TASK_ID, title: 'Retitled' },
      basis,
      MUTATION_ID,
    )
    const body = JSON.parse(command.commandBytes) as {
      base_values: Record<string, string>
      fields: Record<string, string>
    }
    // `CommandController.decode_edit` refuses a mismatched pair before any
    // merge runs, and `Merge.three_way` refuses it again.
    expect(Object.keys(body.fields).sort()).toEqual(Object.keys(body.base_values).sort())
    expect(body.base_values).toEqual({ notes: basis.baseNotes, title: basis.baseTitle })
    expect(body.fields).toEqual({ notes: 'mine', title: 'Retitled' })
  })

  it('carries the basis revision, never a fabricated one', () => {
    const command = buildOutboundCommand({ kind: 'lifecycle', lifecycle: 'complete', taskId: TASK_ID }, basis, MUTATION_ID)
    expect((JSON.parse(command.commandBytes) as { expected_revision: number }).expected_revision).toBe(4)
  })

  it('refuses a basis revision below the contract minimum of 1', () => {
    expect(() =>
      buildOutboundCommand({ kind: 'lifecycle', lifecycle: 'trash', taskId: TASK_ID }, { ...basis, expectedRevision: 0 }, MUTATION_ID),
    ).toThrow('outbound command basis revision is invalid')
  })

  it('refuses an empty or oversized title rather than queueing bytes the server will refuse', () => {
    for (const title of ['   ', 'x'.repeat(513)]) {
      expect(() => buildOutboundCommand({ kind: 'edit', notes: '', taskId: TASK_ID, title }, basis, MUTATION_ID)).toThrow()
    }
  })

  it('scopes every command to its own task so ordering can be enforced by resource key', () => {
    for (const { intent } of cases) {
      expect(buildOutboundCommand(intent, basis, MUTATION_ID).resourceKeys).toEqual([`task:${TASK_ID}`])
    }
  })

  it('carries a title in the effect of a lifecycle command, so an outbox replay cannot blank the row', () => {
    const command = buildOutboundCommand({ kind: 'lifecycle', lifecycle: 'trash', taskId: TASK_ID }, basis, MUTATION_ID)
    expect(command.effect.snapshot.title).toBe(basis.baseTitle)
    expect(command.effect.entityId).toBe(TASK_ID)
  })
})
