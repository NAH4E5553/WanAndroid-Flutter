// Execute the adapted action's actual posting script with an in-memory GitHub.
// No network, model, real credentials, or real GitHub writes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
const helper = require(path.join(input.actionRoot, 'scripts/github-actions/post-review-comments.js'));
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const head = 'b'.repeat(40);
const base = 'a'.repeat(40);
const manifest = {terminal_state: 'complete', input: {resolved_head: head}};

for (const name of ['OCR_SUCCESS_DELAY', 'OCR_FAILURE_DELAY', 'OCR_MAX_RETRIES',
  'OCR_READ_SUCCESS_DELAY', 'OCR_READ_LOW_REMAINING_SPACING']) {
  process.env[name] = '0';
}
Object.assign(process.env, {
  GITHUB_ACTION_PATH: input.actionRoot,
  OCR_ACTION_ROOT: input.actionRoot,
  OCR_RESULT_PATH: '/virtual/result.json',
  OCR_BASE_REF: 'main', OCR_MERGE_BASE: base,
  OCR_CONFIG_FINGERPRINT: 'fixture-fingerprint',
  OCR_RANGE_MODE: 'full', OCR_RANGE_REASON: 'base_changed',
  OCR_RANGE_FROM: '', OCR_RANGE_TO: head, OCR_CHECKPOINT_CARRY: '',
});

async function scenario(raw, {failApi = false, failInline = false, noop = false} = {}) {
  const logs = [], failures = [], bodies = [], outputs = {};
  const summary = [];
  const apiError = () => Object.assign(new Error(input.sentinel), {status: 400});
  const publish = async params => {
    if (failApi) throw apiError();
    bodies.push(params.body);
    const data = {id: 1, html_url: 'https://example.invalid/review', body: params.body,
      user: {login: 'github-actions[bot]', type: 'Bot'}};
    summary.splice(0, summary.length, data);
    return {data};
  };
  const github = {rest: {
    users: {getAuthenticated: async () => ({data: {login: 'github-actions[bot]'}})},
    issues: {listComments: async () => ({data: summary}), createComment: publish, updateComment: publish},
    pulls: {
      get: async () => ({data: {head: {sha: head}}}),
      listReviewComments: async () => ({data: []}),
      listReviews: async () => ({data: []}),
      createReview: async params => {
        if (failInline) throw apiError();
        bodies.push(params.body, ...params.comments.map(c => c.body));
        return {data: {id: 2}, headers: {}};
      },
      createReviewComment: async () => {throw apiError();},
    },
  }};
  github.paginate = async (method, params) => (await method(params)).data;
  const core = {
    info: value => logs.push(value), warning: value => logs.push(value),
    setFailed: value => failures.push(value), setOutput: (name, value) => {outputs[name] = value;},
  };
  const mockFs = {
    existsSync: fs.existsSync,
    readFileSync: filename => {
      if (filename === '/virtual/result.json') return raw;
      throw new Error(input.sentinel); // Reading stderr is never allowed.
    },
  };
  process.env.OCR_RANGE_REASON = noop ? 'same_head_noop' : 'base_changed';
  const context = {repo: {owner: 'fixture', repo: 'fixture'}, issue: {number: 1},
    runId: 1, runAttempt: 1, eventName: 'pull_request', payload: {pull_request: {head: {sha: head}}}};
  await new AsyncFunction('require', 'github', 'context', 'core', input.script)(
    module => module === 'fs' ? mockFs : require(module), github, context, core,
  );
  assert(!JSON.stringify({logs, failures, bodies, outputs}).includes(input.sentinel),
    'Raw diagnostic data escaped through logs, comments, or outputs');
  return {logs, failures, bodies, outputs};
}

(async () => {
  for (const raw of [input.sentinel, '{}', 'null', '[]',
    JSON.stringify({comments: [], manifest: {terminal_state: 'partial'}, message: input.sentinel}),
    JSON.stringify({comments: {}, manifest}),
  ]) {
    const result = await scenario(raw);
    assert.equal(result.failures.length, 1);
    assert.equal(result.bodies.length, 0);
  }
  const empty = await scenario(JSON.stringify({comments: [], manifest, message: input.sentinel}));
  assert.equal(empty.failures.length, 0);
  assert(empty.bodies.some(body => body.includes('Review completed with no findings')));
  assert.equal(empty.outputs.checkpoint_after, head);

  const finding = {file: 'feature/home/Example.kt', start_line: 0, end_line: 0,
    content: 'A reproducible fixture finding', severity: 'high', category: 'bug'};
  const normal = await scenario(JSON.stringify({comments: [finding], manifest,
    warnings: [{message: input.sentinel, file: input.sentinel}], message: input.sentinel}));
  assert.equal(normal.failures.length, 0);
  assert(normal.bodies.some(body => body.includes('A reproducible fixture finding')));
  assert(normal.bodies.some(body => body.includes('warning details suppressed')));

  const failed = await scenario(JSON.stringify({comments: [], manifest}), {failApi: true});
  assert.equal(failed.failures.length, 1);
  assert.equal(failed.outputs.checkpoint_after, undefined);

  const inlineFailure = await scenario(JSON.stringify({comments: [{...finding, start_line: 2, end_line: 2}], manifest}), {failInline: true});
  assert(inlineFailure.bodies.some(body => body.includes('raw error details suppressed')));
  assert.notEqual(inlineFailure.outputs.checkpoint_after, head);

  const noop = await scenario(input.sentinel, {noop: true});
  assert.equal(noop.failures.length, 0);
  assert.equal(noop.bodies.length, 0);

  const range = await helper.resolveCheckpointRange({
    enabled: true, sticky: true, headSha: head, baseRef: 'main', mergeBase: base,
    fingerprint: 'fixture', prNumber: 1, read: {payload: null, raw: ''},
  });
  assert.equal(range.mode, 'full');
  console.log('OCR posting privacy fixtures passed');
})().catch(() => {
  // Test failure must not itself print the private fixture or response body.
  console.error('OCR posting privacy fixture failed');
  process.exitCode = 1;
});
