"""Run actual Nemo inference with the iOS C++ bridge on the macOS build host."""
import hashlib, json, platform, subprocess, sys
from prepare_native import (ROOT,VENDOR,CORE_VERSION,ORT_VERSION,NEMO_SHA256,
                            release,asset,extract,find_one)

def main():
    if sys.platform != 'darwin': raise SystemExit('This inference check runs on the macOS build host.')
    model=VENDOR/'voice/model.vvm'
    if hashlib.sha256(model.read_bytes()).hexdigest()!=NEMO_SHA256:
        raise ValueError('Inference test requires the exact pinned Nemo model')
    arch='arm64' if platform.machine()=='arm64' else 'x64'
    ort_arch='arm64' if arch=='arm64' else 'x86_64'
    core=extract(asset(release('voicevox_core',CORE_VERSION),f'voicevox_core-osx-{arch}-{CORE_VERSION}\\.zip'))
    ort=extract(asset(release('onnxruntime-builder','voicevox_onnxruntime-'+ORT_VERSION),
                      f'voicevox_onnxruntime-osx-{ort_arch}-{ORT_VERSION}\\.tgz'))
    library=find_one(core,'libvoicevox_core.dylib')
    runtimes=[p for p in ort.rglob('*voicevox_onnxruntime*.dylib') if p.is_file()]
    if not runtimes:raise ValueError('Official macOS ONNX Runtime is missing')
    runtime=max(runtimes,key=lambda p:p.stat().st_size)
    out=ROOT/'ios/build/cloud';out.mkdir(parents=True,exist_ok=True)
    binary=out/'nemo-runtime-test'
    subprocess.run(['clang++','-std=c++17',str(ROOT/'native/LTNative.cpp'),str(ROOT/'tests/nemo_runtime.cpp'),
        '-I'+str(ROOT/'native'),'-I'+str(VENDOR/'include'),'-L'+str(library.parent),
        '-lvoicevox_core','-Wl,-rpath,'+str(library.parent),'-o',str(binary)],check=True)
    result=subprocess.run([str(binary),str(VENDOR/'voice/dictionary'),str(model),str(runtime)],
                          check=True,capture_output=True,text=True,timeout=180)
    report=json.loads(result.stdout)
    if len(report['voices'])!=9:raise ValueError('Not all Nemo voices were synthesized')
    report.update(model_sha256=NEMO_SHA256,core_version=CORE_VERSION,onnxruntime_version=ORT_VERSION,
                  iphone_playback_verified=False,scope='Actual macOS inference via the iOS C++ bridge. iPhone playback and latency need device tests.')
    (out/'nemo-runtime.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Actual VOICEVOX Nemo inference: all 9 styles produced non-silent WAV audio on macOS.')

if __name__=='__main__':main()
