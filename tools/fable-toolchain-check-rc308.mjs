#!/usr/bin/env node
/**
 * RC308 — source-pinned Flutter 3.50 Android toolchain preflight.
 * Read-only: never installs SDKs, upgrades Flutter, runs Gradle or pub get.
 * --installed additionally calls ONLY 'flutter --version --machine' and
 * 'java -version', to fail fast before the operator chooses to build.
 */
import {readFileSync} from 'node:fs';
import {execFileSync,spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {resolve,join} from 'node:path';

const root=resolve(fileURLToPath(new URL('..',import.meta.url)));
const read=p=>readFileSync(join(root,p),'utf8');
const lock=JSON.parse(read('toolchain/fable-flutter-3.50.json'));
function check(yes,why){if(!yes)throw Error(why);}
function versionText(source,pattern,why){
  const found=source.match(pattern);
  check(found,why);
  return found[1];
}
function main(){
  const args=process.argv.slice(2).filter(a=>a!=='--');
  check(args.every(x=>['--installed','--source-only','--json','--help'].includes(x)),
    'Flags: --source-only [default], --installed, --json, --help');
  if(args.includes('--help')){
    console.log('pnpm run fable:toolchain:check -- --source-only');
    console.log('pnpm run fable:toolchain:check -- --installed');
    console.log('Only verifies. No SDK download, flutter upgrade, pub get or Gradle build.');
    return;
  }
  const expected=lock.android;
  const pubspec=read('pubspec.yaml');
  check(pubspec.includes("sdk: '>=3.14.0 <3.15.0'")&&
        pubspec.includes("flutter: '>=3.50.0 <3.51.0'"),
    'Root pubspec SDK bounds differ from Flutter 3.50 / Dart 3.14');
  const settings=read('android/settings.gradle.kts');
  check(versionText(settings,/id\("com\.android\.application"\) version "([^"]+)"/,
    'AGP plugin missing')===expected.androidGradlePlugin,'Unexpected AGP');
  check(versionText(settings,/id\("org\.jetbrains\.kotlin\.android"\) version "([^"]+)"/,
    'Kotlin plugin version missing')===expected.kotlinGradlePlugin,'Unexpected Kotlin Gradle plugin');
  const wrapper=read('android/gradle/wrapper/gradle-wrapper.properties');
  check(versionText(wrapper,/distributionUrl=.*gradle-([0-9.]+)-all\.zip/,
    'Gradle Wrapper version missing')===expected.gradleWrapper,'Unexpected Gradle');
  const props=read('android/gradle.properties');
  check(props.includes('android.builtInKotlin='+expected.builtInKotlin)&&
        props.includes('android.newDsl='+expected.newDsl),
    'Kotlin/Gradle DSL mode does not match reviewed source');
  const app=read('android/app/build.gradle.kts');
  for(const [name,value] of [
    ['compileSdk',expected.compileSdk],['targetSdk',expected.targetSdk],
    ['minSdk',expected.minSdk],['ndkVersion',expected.ndk],
    ['buildToolsVersion',expected.buildTools]
  ]){
    const quoted=typeof value==='string'?'\"'+value+'\"':String(value);
    check(app.includes(name+' = '+quoted),'Unexpected Android '+name);
  }
  check(app.includes('JavaVersion.VERSION_17')&&app.includes('JvmTarget.JVM_17'),
    'JVM 17 bytecode expected');
  const out={kind:lock.kind,sourceOnly:true,
    flutter:lock.flutter.version,dart:lock.dart.version,
    gradle:expected.gradleWrapper,agp:expected.androidGradlePlugin,
    kotlin:expected.kotlinGradlePlugin,java:expected.javaMajor,
    status:'SOURCE_CONFIGURATION_MATCHES',
    installedChecked:false,buildExecuted:false,productionReady:false};
  if(args.includes('--installed')){
    const run=(bin,cmd)=>{
      try{return execFileSync(bin,cmd,{
        encoding:'utf8',timeout:30000,windowsHide:true,
        stdio:['ignore','pipe','pipe'],
      });}catch(error){
        const desc=error.stderr?.toString()||error.message;
        throw Error('Cannot check '+bin+': '+desc.slice(0,300));
      }
    };
    // On Windows flutter is a .bat script, so invoke it through cmd.exe.
    // Fixed arguments only; no user-controlled command is interpolated.
    const flutter=JSON.parse(process.platform==='win32'
      ?run('cmd.exe',['/d','/s','/c','flutter --version --machine'])
      :run('flutter',['--version','--machine']));
    check(flutter.frameworkVersion===lock.flutter.version,
      'Installed Flutter '+flutter.frameworkVersion+' is not '+lock.flutter.version);
    check(typeof flutter.dartSdkVersion==='string'&&
      flutter.dartSdkVersion.startsWith(lock.dart.version),
      'Installed Dart '+flutter.dartSdkVersion+' is not '+lock.dart.version);
    const java=process.platform==='win32'?'java.exe':'java';
    const javaResult=spawnSync(java,['-version'],{
      encoding:'utf8',timeout:15000,windowsHide:true,
      stdio:['ignore','pipe','pipe']
    });
    check(javaResult.status===0&&!javaResult.error,
      'Java not accessible: '+String(javaResult.stderr||javaResult.error).slice(0,150));
    const javaVersion=(javaResult.stderr||'')+(javaResult.stdout||'');
    const javaMatch=javaVersion.match(/version\s+"(\d+)[^"]*"/);
    check(javaMatch&&Number(javaMatch[1])>=expected.javaMajor,
      'Java 17+ is required by AGP and Flutter; detected '+javaVersion.slice(0,120));
    out.installedChecked=true;
    out.status='INSTALLED_TOOLCHAIN_MATCHES';
    out.javaInstalledMajor=Number(javaMatch[1]);
  }
  if(args.includes('--json'))console.log(JSON.stringify(out,null,2));
  else{
    console.log('Fable verified toolchain: Flutter '+out.flutter+
      ' / Dart '+out.dart+' / Gradle '+out.gradle+
      ' / AGP '+out.agp+' / Kotlin '+out.kotlin);
    console.log(out.status);
    console.log('No tools installed, Flutter upgraded, dependencies downloaded, or builds executed by this script.');
  }
}
try{main()}catch(error){
  console.error('Fable toolchain rejected: '+error.message);
  process.exitCode=2;
}
