import { z } from 'zod'

const recoveryActionCodeSchema = z.enum([
  'inspect', 'retry', 'check_again', 'review', 'review_conflict', 'sign_in', 'export',
  'remove_local_data', 'retry_save', 'retry_opening', 'show_recovery_options',
])
const desktopPresentationKindSchema = z.enum([
  'healthy', 'opening', 'preparing', 'updating', 'offline', 'retryable_failure',
  'local_saved', 'uncertain', 'rejected', 'conflict', 'authentication_required',
  'namespace_mismatch', 'local_save_failure', 'store_unavailable',
])
const recoveryActionSchema = z.object({
  code: recoveryActionCodeSchema,
  label: z.string().min(1).max(80),
}).strict()
const desktopPresentationSummarySchema = z.object({
  actions: z.array(recoveryActionSchema).max(3),
  copy: z.string().min(1).max(240).nullable(),
  count: z.number().int().min(0).max(99).nullable(),
  kind: desktopPresentationKindSchema,
  lastSuccessfulContact: z.string().min(1).max(80).nullable(),
}).strict()
const desktopPresentationSchema = z.object({
  sequence: z.number().int().nonnegative(),
  summary: desktopPresentationSummarySchema,
  surfaces: z.object({
    panel: desktopPresentationSummarySchema,
    row: desktopPresentationSummarySchema,
    shell: desktopPresentationSummarySchema,
  }).strict(),
}).strict()

export { desktopPresentationSchema }
