import test from 'node:test';
import assert from 'node:assert/strict';
import { startupObservation, safeStartupError } from './browser-startup-observation.mjs';
test('observation emits only bounded codes and never raw error/path/URL text', () => {
  const o = startupObservation();o.error({code:'ENOENT',message:'PRIVATE C:\\profile\\secret'});
  o.spawnedError({code:'UNKNOWN_PRIVATE_CODE'});o.stderr(Buffer.from('DevTools listening on ws://127.0.0.1:1234/private-id\nPRIVATEPROFILE processSingleton'));
  o.file({size:99_999_999,isSymbolicLink:()=>false});o.exited(2,'PRIVATE_SIGNAL');
  const snapshot=o.snapshot({exitCode:2,signalCode:null},999999);const serialized=JSON.stringify(snapshot);
  assert.equal(snapshot.lastError,'ENOENT');assert.equal(snapshot.spawnError,'OTHER');assert.equal(snapshot.signal,'OTHER');
  assert.equal(snapshot.lastFileBytes,1_048_576);assert.equal(snapshot.fileBytesCapped,true);assert.equal(snapshot.elapsedMilliseconds,120000);
  assert.equal(snapshot.stderrIndicators.devtoolsListening,true);assert.equal(snapshot.stderrIndicators.profileInUse,true);
  assert.doesNotMatch(serialized,/PRIVATE|127\.0\.0\.1|ws:\/\/|1234/);
});
test('snapshot freezes pre-cleanup state and records exact parse stage',()=>{
  const o=startupObservation();o.stage('port');o.error({code:'ERR_ASSERTION'});
  const snapshot=o.snapshot({exitCode:null,signalCode:null},10000);o.exited(0,null);o.stage('ready');
  assert.equal(snapshot.rootAliveAtObservation,true);assert.equal(snapshot.lastStage,'port');assert.equal(snapshot.exitObserved,false);
  assert.equal(o.state.exitObserved,true);assert.throws(()=>o.stage('PRIVATE_PATH'));
});
test('stderr inspection and scalar ranges are bounded without retaining raw chunks',()=>{
  const o=startupObservation();o.stderr(Buffer.alloc(2_000_000,65));o.exited(Number.MAX_SAFE_INTEGER,null);
  assert.equal(o.state.stderrBytes,1_048_576);assert.equal(o.state.stderrBytesCapped,true);assert.equal(o.state.exitCode,null);
  assert.equal(safeStartupError({code:'EACCES'}),'EACCES');assert.equal(safeStartupError(new Error('secret')),'OTHER');
});
