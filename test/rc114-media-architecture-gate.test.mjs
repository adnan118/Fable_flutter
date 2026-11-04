import test from 'node:test';
import assert from 'node:assert/strict';
import {auditMediaLayerFile,auditMediaArchitecture} from '../tools/enforce-media-architecture-rc114.mjs';

const path='packages/features/fable_media/lib/src/domain/check.dart';

test('RC114 new Media layers have correct import graph and typed public boundaries',()=>{
  const findings=auditMediaArchitecture(process.cwd());
  assert.deepEqual(findings,[],findings.join('\n'));
});

test('RC114 Domain rejects Flutter/Dio/remote and application imports',()=>{
  for(const source of [
    "import 'package:flutter/widgets.dart';",
    "import 'package:dio/dio.dart';",
    "import '../data/fable_media_byte_source.dart';",
    "import '../application/read_media_range_use_case.dart';",
    "import 'dart:io';",
    "Future<dynamic> parse();",
    "Future<Map<String, dynamic>> get();",
  ]){
    assert.ok(auditMediaLayerFile('domain',source,path).length>0,source);
  }
});

test('RC114 Application cannot reach data adapters, Flutter or raw network contracts',()=>{
  for(const source of [
    "import 'package:fable_core/fable_core.dart';",
    "import '../data/fable_media_byte_source.dart';",
    "import 'package:flutter/foundation.dart';",
    "import '../presentation/media_range_controller.dart';",
    "Response<dynamic> deserialize();",
  ]){
    assert.ok(auditMediaLayerFile('application',source,
      'packages/features/fable_media/lib/src/application/example.dart').length>0,
      source);
  }
});

test('RC114 Presentation cannot depend on data adapters, Dio or Fable core',()=>{
  for(const source of [
    "import 'package:dio/dio.dart';",
    "import 'package:fable_core/fable_core.dart';",
    "import '../data/fable_media_byte_source.dart';",
    "import '../protected_media_playback_repository.dart';",
    "import 'package:shared_preferences/shared_preferences.dart';",
  ]){
    assert.ok(auditMediaLayerFile('presentation',source,
      'packages/features/fable_media/lib/src/presentation/check.dart').length>0,source);
  }
});

test('RC114 explicit Data adapter may depend on verified transport and domain',()=>{
  assert.deepEqual(auditMediaLayerFile('data',[
    "import 'package:dio/dio.dart';",
    "import 'package:fable_core/fable_core.dart';",
    "import '../domain/media_byte_source.dart';",
    "import '../protected_media_playback_repository.dart';",
  ].join('\n'),'packages/features/fable_media/lib/src/data/adapter.dart'),[]);
});

test('RC114 typed layers allow Dart collection/value APIs and real domain imports',()=>{
  assert.deepEqual(auditMediaLayerFile('domain',[
    "import 'dart:typed_data';",
    "import './media_byte_range.dart';",
    'final class MediaRange {}',
  ].join('\n'),path),[]);
  assert.deepEqual(auditMediaLayerFile('application',[
    "import '../domain/media_byte_range.dart';",
    "import 'dart:async';",
    'final class Execute {}',
  ].join('\n'),'packages/features/fable_media/lib/src/application/execute.dart'),[]);
});
