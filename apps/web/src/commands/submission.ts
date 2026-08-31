type SubmissionErrorClassification<Rejection> =
  | { kind: 'authentication_required' }
  | { kind: 'conflict'; rejection: Rejection }
  | { kind: 'not_found' }
  | { kind: 'rejected'; rejection: Rejection }
  | { kind: 'unknown' }

type RecoveryOperation = 'lookup' | 'send'

type ExactSubmissionState<Request, Acknowledgement, Rejection> =
  | { kind: 'not_submitted'; request: Request }
  | { kind: 'in_flight'; operation: RecoveryOperation; request: Request }
  | { kind: 'unknown'; request: Request }
  | {
      kind: 'authentication_required'
      operation: RecoveryOperation
      request: Request
    }
  | {
      acknowledgement: Acknowledgement
      kind: 'acknowledged'
      request: Request
    }
  | { kind: 'rejected'; rejection: Rejection; request: Request }
  | { kind: 'conflict'; rejection: Rejection; request: Request }

type ExactSubmissionOptions<Request, Acknowledgement, Rejection> = {
  classifyError: (error: unknown) => SubmissionErrorClassification<Rejection>
  lookup: (request: Request) => Promise<Acknowledgement>
  matchesAcknowledgement: (acknowledgement: Acknowledgement) => boolean
  onStateChange?: (state: ExactSubmissionState<Request, Acknowledgement, Rejection>) => void
  request: Request
  send: (request: Request, csrfToken: string) => Promise<Acknowledgement>
}

class ExactSubmission<Request, Acknowledgement, Rejection> {
  readonly #options: ExactSubmissionOptions<Request, Acknowledgement, Rejection>
  #epoch = 0
  #state: ExactSubmissionState<Request, Acknowledgement, Rejection>

  constructor(options: ExactSubmissionOptions<Request, Acknowledgement, Rejection>) {
    this.#options = options
    this.#state = { kind: 'not_submitted', request: options.request }
  }

  get snapshot(): ExactSubmissionState<Request, Acknowledgement, Rejection> {
    return this.#state
  }

  async submit(csrfToken: string): Promise<void> {
    await this.#run('send', csrfToken)
  }

  async check(csrfToken: string): Promise<void> {
    await this.#run('lookup', csrfToken)
  }

  async retry(csrfToken: string): Promise<void> {
    await this.#run('send', csrfToken)
  }

  async resumeAfterAuthentication(csrfToken: string): Promise<void> {
    if (this.#state.kind !== 'authentication_required') return
    await this.#run(this.#state.operation, csrfToken)
  }

  fence(): void {
    this.#epoch += 1
    this.#setState({ kind: 'not_submitted', request: this.#options.request })
  }

  async #run(operation: RecoveryOperation, csrfToken: string): Promise<void> {
    if (this.#state.kind === 'in_flight' || this.#state.kind === 'acknowledged') return

    const epoch = ++this.#epoch
    this.#setState({ kind: 'in_flight', operation, request: this.#options.request })

    try {
      const acknowledgement =
        operation === 'send'
          ? await this.#options.send(this.#options.request, csrfToken)
          : await this.#options.lookup(this.#options.request)

      if (epoch !== this.#epoch) return
      if (!this.#options.matchesAcknowledgement(acknowledgement)) {
        this.#setState({ kind: 'unknown', request: this.#options.request })
        return
      }

      this.#setState({ acknowledgement, kind: 'acknowledged', request: this.#options.request })
    } catch (error) {
      if (epoch !== this.#epoch) return
      const classification = this.#options.classifyError(error)

      if (classification.kind === 'authentication_required') {
        this.#setState({
          kind: 'authentication_required',
          operation,
          request: this.#options.request,
        })
      } else if (classification.kind === 'conflict') {
        this.#setState({
          kind: 'conflict',
          rejection: classification.rejection,
          request: this.#options.request,
        })
      } else if (classification.kind === 'rejected') {
        this.#setState({
          kind: 'rejected',
          rejection: classification.rejection,
          request: this.#options.request,
        })
      } else if (classification.kind === 'not_found' && operation === 'lookup') {
        this.#setState({ kind: 'unknown', request: this.#options.request })
        await this.#run('send', csrfToken)
      } else {
        this.#setState({ kind: 'unknown', request: this.#options.request })
      }
    }
  }

  #setState(state: ExactSubmissionState<Request, Acknowledgement, Rejection>): void {
    this.#state = state
    this.#options.onStateChange?.(state)
  }
}

const createExactSubmission = <Request, Acknowledgement, Rejection>(
  options: ExactSubmissionOptions<Request, Acknowledgement, Rejection>,
) => new ExactSubmission(options)

type TaskSubmissionState = ExactSubmissionState<
  PreparedTaskCommand,
  CommandAcknowledgement,
  KeeplingApiError
>

const classifyKeeplingError = (
  error: unknown,
): SubmissionErrorClassification<KeeplingApiError> => {
  if (!(error instanceof KeeplingApiError)) return { kind: 'unknown' }
  if (error.problem.status >= 500) return { kind: 'unknown' }
  if (error.problem.code === 'authentication_required') {
    return { kind: 'authentication_required' }
  }
  if (error.problem.code === 'mutation_not_found') return { kind: 'not_found' }
  if (error.conflict || error.problem.code.endsWith('_conflict')) {
    return { kind: 'conflict', rejection: error }
  }
  return { kind: 'rejected', rejection: error }
}

const createTaskSubmission = (
  request: PreparedTaskCommand,
  onStateChange?: (state: TaskSubmissionState) => void,
) =>
  createExactSubmission({
    classifyError: classifyKeeplingError,
    lookup: (original) => getMutation(original.mutationId),
    matchesAcknowledgement: (acknowledgement) =>
      acknowledgement.mutationId === request.mutationId &&
      acknowledgement.taskId === request.taskId,
    onStateChange,
    request,
    send: submitPreparedTaskCommand,
  })

export { createExactSubmission, createTaskSubmission }
export type {
  ExactSubmission,
  ExactSubmissionOptions,
  ExactSubmissionState,
  SubmissionErrorClassification,
  TaskSubmissionState,
}
import {
  getMutation,
  KeeplingApiError,
  submitPreparedTaskCommand,
  type CommandAcknowledgement,
  type PreparedTaskCommand,
} from '@/api/keepling'
