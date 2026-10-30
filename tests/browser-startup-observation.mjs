// Diagnostics only: fixed enums and bounded scalars, never endpoint/profile text.
const cap = (value, maximum = 1_048_576) => Number.isFinite(value) ? Math.max(0, Math.min(maximum, Math.floor(value))) : 0;
const errors = new Set(['ENOENT', 'EACCES', 'EPERM', 'EINVAL', 'ENOMEM', 'EBUSY', 'EIO', 'EISDIR', 'ENOTDIR', 'ERR_ASSERTION']);
const stages = new Set(['spawn', 'stat', 'file-type', 'read', 'port', 'path', 'ready']);
export function safeStartupError(error) { return errors.has(error?.code) ? error.code : 'OTHER'; }
export function startupObservation() {
  const state = {
    pollCount: 0, lastStage: 'spawn', lastError: 'NONE', fileSeen: false,
    lastFileBytes: 0, fileBytesCapped: false, fileSymlink: false,
    formatValid: false, spawnError: 'NONE', exitObserved: false,
    exitCode: null, signal: 'NONE', rootAliveAtObservation: false,
    elapsedMilliseconds: 0, stderrBytes: 0, stderrBytesCapped: false,
    stderrIndicators: { devtoolsListening: false, addressInUse: false, profileInUse: false, remoteDebuggingPolicy: false, outOfMemory: false, sandboxFailure: false },
  };
  return {
    state,
    stage(value) { if (!stages.has(value)) throw new Error('INVALID_STARTUP_STAGE'); state.lastStage = value; },
    error(error) { state.lastError = safeStartupError(error); },
    file(stats) { state.fileSeen = true; state.lastFileBytes = cap(stats.size); state.fileBytesCapped = stats.size > 1_048_576; state.fileSymlink = stats.isSymbolicLink(); },
    spawnedError(error) { state.spawnError = safeStartupError(error); },
    exited(code, signal) { state.exitObserved = true; state.exitCode = Number.isInteger(code) && code >= -2147483648 && code <= 4294967295 ? code : null; state.signal = ['SIGTERM', 'SIGKILL', 'SIGINT'].includes(signal) ? signal : signal ? 'OTHER' : 'NONE'; },
    stderr(data) {
      const previous = state.stderrBytes;state.stderrBytes = cap(previous + data.length);state.stderrBytesCapped ||= previous + data.length > 1_048_576;
      // Only inspect a bounded current chunk. No raw bytes, lines, paths or URLs
      // survive this call. A split indicator may be missed, never reconstructed.
      const text = data.subarray(0, 8192).toString('utf8').toLowerCase();
      const known = state.stderrIndicators;
      known.devtoolsListening ||= text.includes('devtools listening');
      known.addressInUse ||= /err_address_in_use|address already in use/.test(text);
      known.profileInUse ||= /profile (?:appears to be|is) in use|processsingleton/.test(text);
      known.remoteDebuggingPolicy ||= /remote debugging.{0,40}(?:policy|not allowed|disabled)/.test(text);
      known.outOfMemory ||= /out of memory|err_insufficient_resources/.test(text);
      known.sandboxFailure ||= /sandbox.{0,30}(?:failed|failure)/.test(text);
    },
    snapshot(child, elapsed) {
      state.rootAliveAtObservation = !!child && child.exitCode === null && child.signalCode === null;
      state.elapsedMilliseconds = cap(elapsed, 120_000);
      return structuredClone(state);
    },
  };
}
