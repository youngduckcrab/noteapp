// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note_database.dart';

// ignore_for_file: type=lint
class $KvTable extends Kv with TableInfo<$KvTable, KvRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KvTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kv';
  @override
  VerificationContext validateIntegrity(
    Insertable<KvRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  KvRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KvRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $KvTable createAlias(String alias) {
    return $KvTable(attachedDatabase, alias);
  }
}

class KvRow extends DataClass implements Insertable<KvRow> {
  final String key;
  final String value;
  const KvRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  KvCompanion toCompanion(bool nullToAbsent) {
    return KvCompanion(key: Value(key), value: Value(value));
  }

  factory KvRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KvRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  KvRow copyWith({String? key, String? value}) =>
      KvRow(key: key ?? this.key, value: value ?? this.value);
  KvRow copyWithCompanion(KvCompanion data) {
    return KvRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KvRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KvRow && other.key == this.key && other.value == this.value);
}

class KvCompanion extends UpdateCompanion<KvRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const KvCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KvCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<KvRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KvCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return KvCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KvCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FoldersTable extends Folders with TableInfo<$FoldersTable, FolderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoldersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameNormMeta = const VerificationMeta(
    'nameNorm',
  );
  @override
  late final GeneratedColumn<String> nameNorm = GeneratedColumn<String>(
    'name_norm',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorArgbMeta = const VerificationMeta(
    'colorArgb',
  );
  @override
  late final GeneratedColumn<int> colorArgb = GeneratedColumn<int>(
    'color_argb',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortKeyMeta = const VerificationMeta(
    'sortKey',
  );
  @override
  late final GeneratedColumn<String> sortKey = GeneratedColumn<String>(
    'sort_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trashRootIdMeta = const VerificationMeta(
    'trashRootId',
  );
  @override
  late final GeneratedColumn<String> trashRootId = GeneratedColumn<String>(
    'trash_root_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldVersionsMeta = const VerificationMeta(
    'fieldVersions',
  );
  @override
  late final GeneratedColumn<String> fieldVersions = GeneratedColumn<String>(
    'field_versions',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    parentId,
    name,
    nameNorm,
    colorArgb,
    icon,
    sortKey,
    createdAt,
    updatedAt,
    deletedAt,
    trashRootId,
    version,
    fieldVersions,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<FolderRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('name_norm')) {
      context.handle(
        _nameNormMeta,
        nameNorm.isAcceptableOrUnknown(data['name_norm']!, _nameNormMeta),
      );
    } else if (isInserting) {
      context.missing(_nameNormMeta);
    }
    if (data.containsKey('color_argb')) {
      context.handle(
        _colorArgbMeta,
        colorArgb.isAcceptableOrUnknown(data['color_argb']!, _colorArgbMeta),
      );
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('sort_key')) {
      context.handle(
        _sortKeyMeta,
        sortKey.isAcceptableOrUnknown(data['sort_key']!, _sortKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_sortKeyMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('trash_root_id')) {
      context.handle(
        _trashRootIdMeta,
        trashRootId.isAcceptableOrUnknown(
          data['trash_root_id']!,
          _trashRootIdMeta,
        ),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('field_versions')) {
      context.handle(
        _fieldVersionsMeta,
        fieldVersions.isAcceptableOrUnknown(
          data['field_versions']!,
          _fieldVersionsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FolderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FolderRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameNorm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_norm'],
      )!,
      colorArgb: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_argb'],
      ),
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      ),
      sortKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sort_key'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      trashRootId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trash_root_id'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      fieldVersions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_versions'],
      ),
    );
  }

  @override
  $FoldersTable createAlias(String alias) {
    return $FoldersTable(attachedDatabase, alias);
  }
}

class FolderRow extends DataClass implements Insertable<FolderRow> {
  final String id;
  final String ownerId;
  final String? parentId;
  final String name;
  final String nameNorm;
  final int? colorArgb;
  final String? icon;
  final String sortKey;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final String? trashRootId;
  final String version;
  final String? fieldVersions;
  const FolderRow({
    required this.id,
    required this.ownerId,
    this.parentId,
    required this.name,
    required this.nameNorm,
    this.colorArgb,
    this.icon,
    required this.sortKey,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.trashRootId,
    required this.version,
    this.fieldVersions,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['name'] = Variable<String>(name);
    map['name_norm'] = Variable<String>(nameNorm);
    if (!nullToAbsent || colorArgb != null) {
      map['color_argb'] = Variable<int>(colorArgb);
    }
    if (!nullToAbsent || icon != null) {
      map['icon'] = Variable<String>(icon);
    }
    map['sort_key'] = Variable<String>(sortKey);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    if (!nullToAbsent || trashRootId != null) {
      map['trash_root_id'] = Variable<String>(trashRootId);
    }
    map['version'] = Variable<String>(version);
    if (!nullToAbsent || fieldVersions != null) {
      map['field_versions'] = Variable<String>(fieldVersions);
    }
    return map;
  }

  FoldersCompanion toCompanion(bool nullToAbsent) {
    return FoldersCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      name: Value(name),
      nameNorm: Value(nameNorm),
      colorArgb: colorArgb == null && nullToAbsent
          ? const Value.absent()
          : Value(colorArgb),
      icon: icon == null && nullToAbsent ? const Value.absent() : Value(icon),
      sortKey: Value(sortKey),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      trashRootId: trashRootId == null && nullToAbsent
          ? const Value.absent()
          : Value(trashRootId),
      version: Value(version),
      fieldVersions: fieldVersions == null && nullToAbsent
          ? const Value.absent()
          : Value(fieldVersions),
    );
  }

  factory FolderRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FolderRow(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      name: serializer.fromJson<String>(json['name']),
      nameNorm: serializer.fromJson<String>(json['nameNorm']),
      colorArgb: serializer.fromJson<int?>(json['colorArgb']),
      icon: serializer.fromJson<String?>(json['icon']),
      sortKey: serializer.fromJson<String>(json['sortKey']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      trashRootId: serializer.fromJson<String?>(json['trashRootId']),
      version: serializer.fromJson<String>(json['version']),
      fieldVersions: serializer.fromJson<String?>(json['fieldVersions']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'parentId': serializer.toJson<String?>(parentId),
      'name': serializer.toJson<String>(name),
      'nameNorm': serializer.toJson<String>(nameNorm),
      'colorArgb': serializer.toJson<int?>(colorArgb),
      'icon': serializer.toJson<String?>(icon),
      'sortKey': serializer.toJson<String>(sortKey),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'trashRootId': serializer.toJson<String?>(trashRootId),
      'version': serializer.toJson<String>(version),
      'fieldVersions': serializer.toJson<String?>(fieldVersions),
    };
  }

  FolderRow copyWith({
    String? id,
    String? ownerId,
    Value<String?> parentId = const Value.absent(),
    String? name,
    String? nameNorm,
    Value<int?> colorArgb = const Value.absent(),
    Value<String?> icon = const Value.absent(),
    String? sortKey,
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    Value<String?> trashRootId = const Value.absent(),
    String? version,
    Value<String?> fieldVersions = const Value.absent(),
  }) => FolderRow(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    parentId: parentId.present ? parentId.value : this.parentId,
    name: name ?? this.name,
    nameNorm: nameNorm ?? this.nameNorm,
    colorArgb: colorArgb.present ? colorArgb.value : this.colorArgb,
    icon: icon.present ? icon.value : this.icon,
    sortKey: sortKey ?? this.sortKey,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    trashRootId: trashRootId.present ? trashRootId.value : this.trashRootId,
    version: version ?? this.version,
    fieldVersions: fieldVersions.present
        ? fieldVersions.value
        : this.fieldVersions,
  );
  FolderRow copyWithCompanion(FoldersCompanion data) {
    return FolderRow(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      name: data.name.present ? data.name.value : this.name,
      nameNorm: data.nameNorm.present ? data.nameNorm.value : this.nameNorm,
      colorArgb: data.colorArgb.present ? data.colorArgb.value : this.colorArgb,
      icon: data.icon.present ? data.icon.value : this.icon,
      sortKey: data.sortKey.present ? data.sortKey.value : this.sortKey,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      trashRootId: data.trashRootId.present
          ? data.trashRootId.value
          : this.trashRootId,
      version: data.version.present ? data.version.value : this.version,
      fieldVersions: data.fieldVersions.present
          ? data.fieldVersions.value
          : this.fieldVersions,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FolderRow(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('nameNorm: $nameNorm, ')
          ..write('colorArgb: $colorArgb, ')
          ..write('icon: $icon, ')
          ..write('sortKey: $sortKey, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('trashRootId: $trashRootId, ')
          ..write('version: $version, ')
          ..write('fieldVersions: $fieldVersions')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    parentId,
    name,
    nameNorm,
    colorArgb,
    icon,
    sortKey,
    createdAt,
    updatedAt,
    deletedAt,
    trashRootId,
    version,
    fieldVersions,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FolderRow &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.parentId == this.parentId &&
          other.name == this.name &&
          other.nameNorm == this.nameNorm &&
          other.colorArgb == this.colorArgb &&
          other.icon == this.icon &&
          other.sortKey == this.sortKey &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.trashRootId == this.trashRootId &&
          other.version == this.version &&
          other.fieldVersions == this.fieldVersions);
}

class FoldersCompanion extends UpdateCompanion<FolderRow> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String?> parentId;
  final Value<String> name;
  final Value<String> nameNorm;
  final Value<int?> colorArgb;
  final Value<String?> icon;
  final Value<String> sortKey;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String?> trashRootId;
  final Value<String> version;
  final Value<String?> fieldVersions;
  final Value<int> rowid;
  const FoldersCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.parentId = const Value.absent(),
    this.name = const Value.absent(),
    this.nameNorm = const Value.absent(),
    this.colorArgb = const Value.absent(),
    this.icon = const Value.absent(),
    this.sortKey = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.trashRootId = const Value.absent(),
    this.version = const Value.absent(),
    this.fieldVersions = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoldersCompanion.insert({
    required String id,
    required String ownerId,
    this.parentId = const Value.absent(),
    required String name,
    required String nameNorm,
    this.colorArgb = const Value.absent(),
    this.icon = const Value.absent(),
    required String sortKey,
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    this.trashRootId = const Value.absent(),
    required String version,
    this.fieldVersions = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       name = Value(name),
       nameNorm = Value(nameNorm),
       sortKey = Value(sortKey),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       version = Value(version);
  static Insertable<FolderRow> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? parentId,
    Expression<String>? name,
    Expression<String>? nameNorm,
    Expression<int>? colorArgb,
    Expression<String>? icon,
    Expression<String>? sortKey,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? trashRootId,
    Expression<String>? version,
    Expression<String>? fieldVersions,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (parentId != null) 'parent_id': parentId,
      if (name != null) 'name': name,
      if (nameNorm != null) 'name_norm': nameNorm,
      if (colorArgb != null) 'color_argb': colorArgb,
      if (icon != null) 'icon': icon,
      if (sortKey != null) 'sort_key': sortKey,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (trashRootId != null) 'trash_root_id': trashRootId,
      if (version != null) 'version': version,
      if (fieldVersions != null) 'field_versions': fieldVersions,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FoldersCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String?>? parentId,
    Value<String>? name,
    Value<String>? nameNorm,
    Value<int?>? colorArgb,
    Value<String?>? icon,
    Value<String>? sortKey,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String?>? trashRootId,
    Value<String>? version,
    Value<String?>? fieldVersions,
    Value<int>? rowid,
  }) {
    return FoldersCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      nameNorm: nameNorm ?? this.nameNorm,
      colorArgb: colorArgb ?? this.colorArgb,
      icon: icon ?? this.icon,
      sortKey: sortKey ?? this.sortKey,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      trashRootId: trashRootId ?? this.trashRootId,
      version: version ?? this.version,
      fieldVersions: fieldVersions ?? this.fieldVersions,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameNorm.present) {
      map['name_norm'] = Variable<String>(nameNorm.value);
    }
    if (colorArgb.present) {
      map['color_argb'] = Variable<int>(colorArgb.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (sortKey.present) {
      map['sort_key'] = Variable<String>(sortKey.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (trashRootId.present) {
      map['trash_root_id'] = Variable<String>(trashRootId.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (fieldVersions.present) {
      map['field_versions'] = Variable<String>(fieldVersions.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoldersCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('nameNorm: $nameNorm, ')
          ..write('colorArgb: $colorArgb, ')
          ..write('icon: $icon, ')
          ..write('sortKey: $sortKey, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('trashRootId: $trashRootId, ')
          ..write('version: $version, ')
          ..write('fieldVersions: $fieldVersions, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NotesTable extends Notes with TableInfo<$NotesTable, NoteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<String> folderId = GeneratedColumn<String>(
    'folder_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleNormMeta = const VerificationMeta(
    'titleNorm',
  );
  @override
  late final GeneratedColumn<String> titleNorm = GeneratedColumn<String>(
    'title_norm',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverJsonMeta = const VerificationMeta(
    'coverJson',
  );
  @override
  late final GeneratedColumn<String> coverJson = GeneratedColumn<String>(
    'cover_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagsJsonMeta = const VerificationMeta(
    'tagsJson',
  );
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
    'tags_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
  );
  static const VerificationMeta _sortKeyMeta = const VerificationMeta(
    'sortKey',
  );
  @override
  late final GeneratedColumn<String> sortKey = GeneratedColumn<String>(
    'sort_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trashRootIdMeta = const VerificationMeta(
    'trashRootId',
  );
  @override
  late final GeneratedColumn<String> trashRootId = GeneratedColumn<String>(
    'trash_root_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldVersionsMeta = const VerificationMeta(
    'fieldVersions',
  );
  @override
  late final GeneratedColumn<String> fieldVersions = GeneratedColumn<String>(
    'field_versions',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageCountMeta = const VerificationMeta(
    'pageCount',
  );
  @override
  late final GeneratedColumn<int> pageCount = GeneratedColumn<int>(
    'page_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstPageIdMeta = const VerificationMeta(
    'firstPageId',
  );
  @override
  late final GeneratedColumn<String> firstPageId = GeneratedColumn<String>(
    'first_page_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastOpenedAtMeta = const VerificationMeta(
    'lastOpenedAt',
  );
  @override
  late final GeneratedColumn<int> lastOpenedAt = GeneratedColumn<int>(
    'last_opened_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    folderId,
    title,
    titleNorm,
    coverJson,
    tagsJson,
    isFavorite,
    sortKey,
    schemaVersion,
    createdAt,
    updatedAt,
    deletedAt,
    trashRootId,
    version,
    fieldVersions,
    pageCount,
    firstPageId,
    lastOpenedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('title_norm')) {
      context.handle(
        _titleNormMeta,
        titleNorm.isAcceptableOrUnknown(data['title_norm']!, _titleNormMeta),
      );
    } else if (isInserting) {
      context.missing(_titleNormMeta);
    }
    if (data.containsKey('cover_json')) {
      context.handle(
        _coverJsonMeta,
        coverJson.isAcceptableOrUnknown(data['cover_json']!, _coverJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_coverJsonMeta);
    }
    if (data.containsKey('tags_json')) {
      context.handle(
        _tagsJsonMeta,
        tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_tagsJsonMeta);
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    } else if (isInserting) {
      context.missing(_isFavoriteMeta);
    }
    if (data.containsKey('sort_key')) {
      context.handle(
        _sortKeyMeta,
        sortKey.isAcceptableOrUnknown(data['sort_key']!, _sortKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_sortKeyMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_schemaVersionMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('trash_root_id')) {
      context.handle(
        _trashRootIdMeta,
        trashRootId.isAcceptableOrUnknown(
          data['trash_root_id']!,
          _trashRootIdMeta,
        ),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('field_versions')) {
      context.handle(
        _fieldVersionsMeta,
        fieldVersions.isAcceptableOrUnknown(
          data['field_versions']!,
          _fieldVersionsMeta,
        ),
      );
    }
    if (data.containsKey('page_count')) {
      context.handle(
        _pageCountMeta,
        pageCount.isAcceptableOrUnknown(data['page_count']!, _pageCountMeta),
      );
    } else if (isInserting) {
      context.missing(_pageCountMeta);
    }
    if (data.containsKey('first_page_id')) {
      context.handle(
        _firstPageIdMeta,
        firstPageId.isAcceptableOrUnknown(
          data['first_page_id']!,
          _firstPageIdMeta,
        ),
      );
    }
    if (data.containsKey('last_opened_at')) {
      context.handle(
        _lastOpenedAtMeta,
        lastOpenedAt.isAcceptableOrUnknown(
          data['last_opened_at']!,
          _lastOpenedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      titleNorm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title_norm'],
      )!,
      coverJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_json'],
      )!,
      tagsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_json'],
      )!,
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      sortKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sort_key'],
      )!,
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      trashRootId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trash_root_id'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      fieldVersions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_versions'],
      ),
      pageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_count'],
      )!,
      firstPageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_page_id'],
      ),
      lastOpenedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_opened_at'],
      ),
    );
  }

  @override
  $NotesTable createAlias(String alias) {
    return $NotesTable(attachedDatabase, alias);
  }
}

class NoteRow extends DataClass implements Insertable<NoteRow> {
  final String id;
  final String ownerId;
  final String? folderId;
  final String title;
  final String titleNorm;
  final String coverJson;
  final String tagsJson;
  final bool isFavorite;
  final String sortKey;
  final int schemaVersion;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final String? trashRootId;
  final String version;
  final String? fieldVersions;
  final int pageCount;
  final String? firstPageId;
  final int? lastOpenedAt;
  const NoteRow({
    required this.id,
    required this.ownerId,
    this.folderId,
    required this.title,
    required this.titleNorm,
    required this.coverJson,
    required this.tagsJson,
    required this.isFavorite,
    required this.sortKey,
    required this.schemaVersion,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.trashRootId,
    required this.version,
    this.fieldVersions,
    required this.pageCount,
    this.firstPageId,
    this.lastOpenedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    if (!nullToAbsent || folderId != null) {
      map['folder_id'] = Variable<String>(folderId);
    }
    map['title'] = Variable<String>(title);
    map['title_norm'] = Variable<String>(titleNorm);
    map['cover_json'] = Variable<String>(coverJson);
    map['tags_json'] = Variable<String>(tagsJson);
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['sort_key'] = Variable<String>(sortKey);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    if (!nullToAbsent || trashRootId != null) {
      map['trash_root_id'] = Variable<String>(trashRootId);
    }
    map['version'] = Variable<String>(version);
    if (!nullToAbsent || fieldVersions != null) {
      map['field_versions'] = Variable<String>(fieldVersions);
    }
    map['page_count'] = Variable<int>(pageCount);
    if (!nullToAbsent || firstPageId != null) {
      map['first_page_id'] = Variable<String>(firstPageId);
    }
    if (!nullToAbsent || lastOpenedAt != null) {
      map['last_opened_at'] = Variable<int>(lastOpenedAt);
    }
    return map;
  }

  NotesCompanion toCompanion(bool nullToAbsent) {
    return NotesCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      folderId: folderId == null && nullToAbsent
          ? const Value.absent()
          : Value(folderId),
      title: Value(title),
      titleNorm: Value(titleNorm),
      coverJson: Value(coverJson),
      tagsJson: Value(tagsJson),
      isFavorite: Value(isFavorite),
      sortKey: Value(sortKey),
      schemaVersion: Value(schemaVersion),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      trashRootId: trashRootId == null && nullToAbsent
          ? const Value.absent()
          : Value(trashRootId),
      version: Value(version),
      fieldVersions: fieldVersions == null && nullToAbsent
          ? const Value.absent()
          : Value(fieldVersions),
      pageCount: Value(pageCount),
      firstPageId: firstPageId == null && nullToAbsent
          ? const Value.absent()
          : Value(firstPageId),
      lastOpenedAt: lastOpenedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastOpenedAt),
    );
  }

  factory NoteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteRow(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      folderId: serializer.fromJson<String?>(json['folderId']),
      title: serializer.fromJson<String>(json['title']),
      titleNorm: serializer.fromJson<String>(json['titleNorm']),
      coverJson: serializer.fromJson<String>(json['coverJson']),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      sortKey: serializer.fromJson<String>(json['sortKey']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      trashRootId: serializer.fromJson<String?>(json['trashRootId']),
      version: serializer.fromJson<String>(json['version']),
      fieldVersions: serializer.fromJson<String?>(json['fieldVersions']),
      pageCount: serializer.fromJson<int>(json['pageCount']),
      firstPageId: serializer.fromJson<String?>(json['firstPageId']),
      lastOpenedAt: serializer.fromJson<int?>(json['lastOpenedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'folderId': serializer.toJson<String?>(folderId),
      'title': serializer.toJson<String>(title),
      'titleNorm': serializer.toJson<String>(titleNorm),
      'coverJson': serializer.toJson<String>(coverJson),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'sortKey': serializer.toJson<String>(sortKey),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'trashRootId': serializer.toJson<String?>(trashRootId),
      'version': serializer.toJson<String>(version),
      'fieldVersions': serializer.toJson<String?>(fieldVersions),
      'pageCount': serializer.toJson<int>(pageCount),
      'firstPageId': serializer.toJson<String?>(firstPageId),
      'lastOpenedAt': serializer.toJson<int?>(lastOpenedAt),
    };
  }

  NoteRow copyWith({
    String? id,
    String? ownerId,
    Value<String?> folderId = const Value.absent(),
    String? title,
    String? titleNorm,
    String? coverJson,
    String? tagsJson,
    bool? isFavorite,
    String? sortKey,
    int? schemaVersion,
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    Value<String?> trashRootId = const Value.absent(),
    String? version,
    Value<String?> fieldVersions = const Value.absent(),
    int? pageCount,
    Value<String?> firstPageId = const Value.absent(),
    Value<int?> lastOpenedAt = const Value.absent(),
  }) => NoteRow(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    folderId: folderId.present ? folderId.value : this.folderId,
    title: title ?? this.title,
    titleNorm: titleNorm ?? this.titleNorm,
    coverJson: coverJson ?? this.coverJson,
    tagsJson: tagsJson ?? this.tagsJson,
    isFavorite: isFavorite ?? this.isFavorite,
    sortKey: sortKey ?? this.sortKey,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    trashRootId: trashRootId.present ? trashRootId.value : this.trashRootId,
    version: version ?? this.version,
    fieldVersions: fieldVersions.present
        ? fieldVersions.value
        : this.fieldVersions,
    pageCount: pageCount ?? this.pageCount,
    firstPageId: firstPageId.present ? firstPageId.value : this.firstPageId,
    lastOpenedAt: lastOpenedAt.present ? lastOpenedAt.value : this.lastOpenedAt,
  );
  NoteRow copyWithCompanion(NotesCompanion data) {
    return NoteRow(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      title: data.title.present ? data.title.value : this.title,
      titleNorm: data.titleNorm.present ? data.titleNorm.value : this.titleNorm,
      coverJson: data.coverJson.present ? data.coverJson.value : this.coverJson,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      sortKey: data.sortKey.present ? data.sortKey.value : this.sortKey,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      trashRootId: data.trashRootId.present
          ? data.trashRootId.value
          : this.trashRootId,
      version: data.version.present ? data.version.value : this.version,
      fieldVersions: data.fieldVersions.present
          ? data.fieldVersions.value
          : this.fieldVersions,
      pageCount: data.pageCount.present ? data.pageCount.value : this.pageCount,
      firstPageId: data.firstPageId.present
          ? data.firstPageId.value
          : this.firstPageId,
      lastOpenedAt: data.lastOpenedAt.present
          ? data.lastOpenedAt.value
          : this.lastOpenedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteRow(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('folderId: $folderId, ')
          ..write('title: $title, ')
          ..write('titleNorm: $titleNorm, ')
          ..write('coverJson: $coverJson, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('sortKey: $sortKey, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('trashRootId: $trashRootId, ')
          ..write('version: $version, ')
          ..write('fieldVersions: $fieldVersions, ')
          ..write('pageCount: $pageCount, ')
          ..write('firstPageId: $firstPageId, ')
          ..write('lastOpenedAt: $lastOpenedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    folderId,
    title,
    titleNorm,
    coverJson,
    tagsJson,
    isFavorite,
    sortKey,
    schemaVersion,
    createdAt,
    updatedAt,
    deletedAt,
    trashRootId,
    version,
    fieldVersions,
    pageCount,
    firstPageId,
    lastOpenedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteRow &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.folderId == this.folderId &&
          other.title == this.title &&
          other.titleNorm == this.titleNorm &&
          other.coverJson == this.coverJson &&
          other.tagsJson == this.tagsJson &&
          other.isFavorite == this.isFavorite &&
          other.sortKey == this.sortKey &&
          other.schemaVersion == this.schemaVersion &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.trashRootId == this.trashRootId &&
          other.version == this.version &&
          other.fieldVersions == this.fieldVersions &&
          other.pageCount == this.pageCount &&
          other.firstPageId == this.firstPageId &&
          other.lastOpenedAt == this.lastOpenedAt);
}

class NotesCompanion extends UpdateCompanion<NoteRow> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String?> folderId;
  final Value<String> title;
  final Value<String> titleNorm;
  final Value<String> coverJson;
  final Value<String> tagsJson;
  final Value<bool> isFavorite;
  final Value<String> sortKey;
  final Value<int> schemaVersion;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String?> trashRootId;
  final Value<String> version;
  final Value<String?> fieldVersions;
  final Value<int> pageCount;
  final Value<String?> firstPageId;
  final Value<int?> lastOpenedAt;
  final Value<int> rowid;
  const NotesCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.folderId = const Value.absent(),
    this.title = const Value.absent(),
    this.titleNorm = const Value.absent(),
    this.coverJson = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.sortKey = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.trashRootId = const Value.absent(),
    this.version = const Value.absent(),
    this.fieldVersions = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.firstPageId = const Value.absent(),
    this.lastOpenedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotesCompanion.insert({
    required String id,
    required String ownerId,
    this.folderId = const Value.absent(),
    required String title,
    required String titleNorm,
    required String coverJson,
    required String tagsJson,
    required bool isFavorite,
    required String sortKey,
    required int schemaVersion,
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    this.trashRootId = const Value.absent(),
    required String version,
    this.fieldVersions = const Value.absent(),
    required int pageCount,
    this.firstPageId = const Value.absent(),
    this.lastOpenedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       title = Value(title),
       titleNorm = Value(titleNorm),
       coverJson = Value(coverJson),
       tagsJson = Value(tagsJson),
       isFavorite = Value(isFavorite),
       sortKey = Value(sortKey),
       schemaVersion = Value(schemaVersion),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       version = Value(version),
       pageCount = Value(pageCount);
  static Insertable<NoteRow> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? folderId,
    Expression<String>? title,
    Expression<String>? titleNorm,
    Expression<String>? coverJson,
    Expression<String>? tagsJson,
    Expression<bool>? isFavorite,
    Expression<String>? sortKey,
    Expression<int>? schemaVersion,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? trashRootId,
    Expression<String>? version,
    Expression<String>? fieldVersions,
    Expression<int>? pageCount,
    Expression<String>? firstPageId,
    Expression<int>? lastOpenedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (folderId != null) 'folder_id': folderId,
      if (title != null) 'title': title,
      if (titleNorm != null) 'title_norm': titleNorm,
      if (coverJson != null) 'cover_json': coverJson,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (sortKey != null) 'sort_key': sortKey,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (trashRootId != null) 'trash_root_id': trashRootId,
      if (version != null) 'version': version,
      if (fieldVersions != null) 'field_versions': fieldVersions,
      if (pageCount != null) 'page_count': pageCount,
      if (firstPageId != null) 'first_page_id': firstPageId,
      if (lastOpenedAt != null) 'last_opened_at': lastOpenedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotesCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String?>? folderId,
    Value<String>? title,
    Value<String>? titleNorm,
    Value<String>? coverJson,
    Value<String>? tagsJson,
    Value<bool>? isFavorite,
    Value<String>? sortKey,
    Value<int>? schemaVersion,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String?>? trashRootId,
    Value<String>? version,
    Value<String?>? fieldVersions,
    Value<int>? pageCount,
    Value<String?>? firstPageId,
    Value<int?>? lastOpenedAt,
    Value<int>? rowid,
  }) {
    return NotesCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      folderId: folderId ?? this.folderId,
      title: title ?? this.title,
      titleNorm: titleNorm ?? this.titleNorm,
      coverJson: coverJson ?? this.coverJson,
      tagsJson: tagsJson ?? this.tagsJson,
      isFavorite: isFavorite ?? this.isFavorite,
      sortKey: sortKey ?? this.sortKey,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      trashRootId: trashRootId ?? this.trashRootId,
      version: version ?? this.version,
      fieldVersions: fieldVersions ?? this.fieldVersions,
      pageCount: pageCount ?? this.pageCount,
      firstPageId: firstPageId ?? this.firstPageId,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<String>(folderId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (titleNorm.present) {
      map['title_norm'] = Variable<String>(titleNorm.value);
    }
    if (coverJson.present) {
      map['cover_json'] = Variable<String>(coverJson.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (sortKey.present) {
      map['sort_key'] = Variable<String>(sortKey.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (trashRootId.present) {
      map['trash_root_id'] = Variable<String>(trashRootId.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (fieldVersions.present) {
      map['field_versions'] = Variable<String>(fieldVersions.value);
    }
    if (pageCount.present) {
      map['page_count'] = Variable<int>(pageCount.value);
    }
    if (firstPageId.present) {
      map['first_page_id'] = Variable<String>(firstPageId.value);
    }
    if (lastOpenedAt.present) {
      map['last_opened_at'] = Variable<int>(lastOpenedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotesCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('folderId: $folderId, ')
          ..write('title: $title, ')
          ..write('titleNorm: $titleNorm, ')
          ..write('coverJson: $coverJson, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('sortKey: $sortKey, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('trashRootId: $trashRootId, ')
          ..write('version: $version, ')
          ..write('fieldVersions: $fieldVersions, ')
          ..write('pageCount: $pageCount, ')
          ..write('firstPageId: $firstPageId, ')
          ..write('lastOpenedAt: $lastOpenedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PagesTable extends Pages with TableInfo<$PagesTable, PageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortKeyMeta = const VerificationMeta(
    'sortKey',
  );
  @override
  late final GeneratedColumn<String> sortKey = GeneratedColumn<String>(
    'sort_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<double> width = GeneratedColumn<double>(
    'width',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<double> height = GeneratedColumn<double>(
    'height',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _backgroundJsonMeta = const VerificationMeta(
    'backgroundJson',
  );
  @override
  late final GeneratedColumn<String> backgroundJson = GeneratedColumn<String>(
    'background_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldVersionsMeta = const VerificationMeta(
    'fieldVersions',
  );
  @override
  late final GeneratedColumn<String> fieldVersions = GeneratedColumn<String>(
    'field_versions',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentRevMeta = const VerificationMeta(
    'contentRev',
  );
  @override
  late final GeneratedColumn<int> contentRev = GeneratedColumn<int>(
    'content_rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    noteId,
    sortKey,
    width,
    height,
    backgroundJson,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    fieldVersions,
    contentRev,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pages';
  @override
  VerificationContext validateIntegrity(
    Insertable<PageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('sort_key')) {
      context.handle(
        _sortKeyMeta,
        sortKey.isAcceptableOrUnknown(data['sort_key']!, _sortKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_sortKeyMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    } else if (isInserting) {
      context.missing(_widthMeta);
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    } else if (isInserting) {
      context.missing(_heightMeta);
    }
    if (data.containsKey('background_json')) {
      context.handle(
        _backgroundJsonMeta,
        backgroundJson.isAcceptableOrUnknown(
          data['background_json']!,
          _backgroundJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_backgroundJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('field_versions')) {
      context.handle(
        _fieldVersionsMeta,
        fieldVersions.isAcceptableOrUnknown(
          data['field_versions']!,
          _fieldVersionsMeta,
        ),
      );
    }
    if (data.containsKey('content_rev')) {
      context.handle(
        _contentRevMeta,
        contentRev.isAcceptableOrUnknown(data['content_rev']!, _contentRevMeta),
      );
    } else if (isInserting) {
      context.missing(_contentRevMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PageRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      sortKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sort_key'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}width'],
      )!,
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}height'],
      )!,
      backgroundJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}background_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      fieldVersions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_versions'],
      ),
      contentRev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}content_rev'],
      )!,
    );
  }

  @override
  $PagesTable createAlias(String alias) {
    return $PagesTable(attachedDatabase, alias);
  }
}

class PageRow extends DataClass implements Insertable<PageRow> {
  final String id;
  final String noteId;
  final String sortKey;
  final double width;
  final double height;
  final String backgroundJson;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final String version;
  final String? fieldVersions;
  final int contentRev;
  const PageRow({
    required this.id,
    required this.noteId,
    required this.sortKey,
    required this.width,
    required this.height,
    required this.backgroundJson,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    this.fieldVersions,
    required this.contentRev,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['note_id'] = Variable<String>(noteId);
    map['sort_key'] = Variable<String>(sortKey);
    map['width'] = Variable<double>(width);
    map['height'] = Variable<double>(height);
    map['background_json'] = Variable<String>(backgroundJson);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<String>(version);
    if (!nullToAbsent || fieldVersions != null) {
      map['field_versions'] = Variable<String>(fieldVersions);
    }
    map['content_rev'] = Variable<int>(contentRev);
    return map;
  }

  PagesCompanion toCompanion(bool nullToAbsent) {
    return PagesCompanion(
      id: Value(id),
      noteId: Value(noteId),
      sortKey: Value(sortKey),
      width: Value(width),
      height: Value(height),
      backgroundJson: Value(backgroundJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      fieldVersions: fieldVersions == null && nullToAbsent
          ? const Value.absent()
          : Value(fieldVersions),
      contentRev: Value(contentRev),
    );
  }

  factory PageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PageRow(
      id: serializer.fromJson<String>(json['id']),
      noteId: serializer.fromJson<String>(json['noteId']),
      sortKey: serializer.fromJson<String>(json['sortKey']),
      width: serializer.fromJson<double>(json['width']),
      height: serializer.fromJson<double>(json['height']),
      backgroundJson: serializer.fromJson<String>(json['backgroundJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<String>(json['version']),
      fieldVersions: serializer.fromJson<String?>(json['fieldVersions']),
      contentRev: serializer.fromJson<int>(json['contentRev']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'noteId': serializer.toJson<String>(noteId),
      'sortKey': serializer.toJson<String>(sortKey),
      'width': serializer.toJson<double>(width),
      'height': serializer.toJson<double>(height),
      'backgroundJson': serializer.toJson<String>(backgroundJson),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<String>(version),
      'fieldVersions': serializer.toJson<String?>(fieldVersions),
      'contentRev': serializer.toJson<int>(contentRev),
    };
  }

  PageRow copyWith({
    String? id,
    String? noteId,
    String? sortKey,
    double? width,
    double? height,
    String? backgroundJson,
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? version,
    Value<String?> fieldVersions = const Value.absent(),
    int? contentRev,
  }) => PageRow(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    sortKey: sortKey ?? this.sortKey,
    width: width ?? this.width,
    height: height ?? this.height,
    backgroundJson: backgroundJson ?? this.backgroundJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    fieldVersions: fieldVersions.present
        ? fieldVersions.value
        : this.fieldVersions,
    contentRev: contentRev ?? this.contentRev,
  );
  PageRow copyWithCompanion(PagesCompanion data) {
    return PageRow(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      sortKey: data.sortKey.present ? data.sortKey.value : this.sortKey,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      backgroundJson: data.backgroundJson.present
          ? data.backgroundJson.value
          : this.backgroundJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      fieldVersions: data.fieldVersions.present
          ? data.fieldVersions.value
          : this.fieldVersions,
      contentRev: data.contentRev.present
          ? data.contentRev.value
          : this.contentRev,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PageRow(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('sortKey: $sortKey, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('backgroundJson: $backgroundJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('fieldVersions: $fieldVersions, ')
          ..write('contentRev: $contentRev')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    noteId,
    sortKey,
    width,
    height,
    backgroundJson,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    fieldVersions,
    contentRev,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PageRow &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.sortKey == this.sortKey &&
          other.width == this.width &&
          other.height == this.height &&
          other.backgroundJson == this.backgroundJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.fieldVersions == this.fieldVersions &&
          other.contentRev == this.contentRev);
}

class PagesCompanion extends UpdateCompanion<PageRow> {
  final Value<String> id;
  final Value<String> noteId;
  final Value<String> sortKey;
  final Value<double> width;
  final Value<double> height;
  final Value<String> backgroundJson;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> version;
  final Value<String?> fieldVersions;
  final Value<int> contentRev;
  final Value<int> rowid;
  const PagesCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.sortKey = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.backgroundJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.fieldVersions = const Value.absent(),
    this.contentRev = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PagesCompanion.insert({
    required String id,
    required String noteId,
    required String sortKey,
    required double width,
    required double height,
    required String backgroundJson,
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String version,
    this.fieldVersions = const Value.absent(),
    required int contentRev,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       noteId = Value(noteId),
       sortKey = Value(sortKey),
       width = Value(width),
       height = Value(height),
       backgroundJson = Value(backgroundJson),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       version = Value(version),
       contentRev = Value(contentRev);
  static Insertable<PageRow> custom({
    Expression<String>? id,
    Expression<String>? noteId,
    Expression<String>? sortKey,
    Expression<double>? width,
    Expression<double>? height,
    Expression<String>? backgroundJson,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? version,
    Expression<String>? fieldVersions,
    Expression<int>? contentRev,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (sortKey != null) 'sort_key': sortKey,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (backgroundJson != null) 'background_json': backgroundJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (fieldVersions != null) 'field_versions': fieldVersions,
      if (contentRev != null) 'content_rev': contentRev,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PagesCompanion copyWith({
    Value<String>? id,
    Value<String>? noteId,
    Value<String>? sortKey,
    Value<double>? width,
    Value<double>? height,
    Value<String>? backgroundJson,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? version,
    Value<String?>? fieldVersions,
    Value<int>? contentRev,
    Value<int>? rowid,
  }) {
    return PagesCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      sortKey: sortKey ?? this.sortKey,
      width: width ?? this.width,
      height: height ?? this.height,
      backgroundJson: backgroundJson ?? this.backgroundJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      fieldVersions: fieldVersions ?? this.fieldVersions,
      contentRev: contentRev ?? this.contentRev,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (sortKey.present) {
      map['sort_key'] = Variable<String>(sortKey.value);
    }
    if (width.present) {
      map['width'] = Variable<double>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<double>(height.value);
    }
    if (backgroundJson.present) {
      map['background_json'] = Variable<String>(backgroundJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (fieldVersions.present) {
      map['field_versions'] = Variable<String>(fieldVersions.value);
    }
    if (contentRev.present) {
      map['content_rev'] = Variable<int>(contentRev.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PagesCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('sortKey: $sortKey, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('backgroundJson: $backgroundJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('fieldVersions: $fieldVersions, ')
          ..write('contentRev: $contentRev, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StrokesTable extends Strokes with TableInfo<$StrokesTable, StrokeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StrokesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageIdMeta = const VerificationMeta('pageId');
  @override
  late final GeneratedColumn<String> pageId = GeneratedColumn<String>(
    'page_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toolMeta = const VerificationMeta('tool');
  @override
  late final GeneratedColumn<String> tool = GeneratedColumn<String>(
    'tool',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorArgbMeta = const VerificationMeta(
    'colorArgb',
  );
  @override
  late final GeneratedColumn<int> colorArgb = GeneratedColumn<int>(
    'color_argb',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<double> width = GeneratedColumn<double>(
    'width',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opacityMeta = const VerificationMeta(
    'opacity',
  );
  @override
  late final GeneratedColumn<double> opacity = GeneratedColumn<double>(
    'opacity',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pressureSensitivityMeta =
      const VerificationMeta('pressureSensitivity');
  @override
  late final GeneratedColumn<double> pressureSensitivity =
      GeneratedColumn<double>(
        'pressure_sensitivity',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _pressureCurveMeta = const VerificationMeta(
    'pressureCurve',
  );
  @override
  late final GeneratedColumn<String> pressureCurve = GeneratedColumn<String>(
    'pressure_curve',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _smoothingMeta = const VerificationMeta(
    'smoothing',
  );
  @override
  late final GeneratedColumn<double> smoothing = GeneratedColumn<double>(
    'smoothing',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _styleExtrasJsonMeta = const VerificationMeta(
    'styleExtrasJson',
  );
  @override
  late final GeneratedColumn<String> styleExtrasJson = GeneratedColumn<String>(
    'style_extras_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pointsMeta = const VerificationMeta('points');
  @override
  late final GeneratedColumn<Uint8List> points = GeneratedColumn<Uint8List>(
    'points',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pointCountMeta = const VerificationMeta(
    'pointCount',
  );
  @override
  late final GeneratedColumn<int> pointCount = GeneratedColumn<int>(
    'point_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minXMeta = const VerificationMeta('minX');
  @override
  late final GeneratedColumn<double> minX = GeneratedColumn<double>(
    'min_x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minYMeta = const VerificationMeta('minY');
  @override
  late final GeneratedColumn<double> minY = GeneratedColumn<double>(
    'min_y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _maxXMeta = const VerificationMeta('maxX');
  @override
  late final GeneratedColumn<double> maxX = GeneratedColumn<double>(
    'max_x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _maxYMeta = const VerificationMeta('maxY');
  @override
  late final GeneratedColumn<double> maxY = GeneratedColumn<double>(
    'max_y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordingIdMeta = const VerificationMeta(
    'recordingId',
  );
  @override
  late final GeneratedColumn<String> recordingId = GeneratedColumn<String>(
    'recording_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recordingOffsetMsMeta = const VerificationMeta(
    'recordingOffsetMs',
  );
  @override
  late final GeneratedColumn<int> recordingOffsetMs = GeneratedColumn<int>(
    'recording_offset_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldVersionsMeta = const VerificationMeta(
    'fieldVersions',
  );
  @override
  late final GeneratedColumn<String> fieldVersions = GeneratedColumn<String>(
    'field_versions',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    pageId,
    noteId,
    tool,
    colorArgb,
    width,
    opacity,
    pressureSensitivity,
    pressureCurve,
    smoothing,
    styleExtrasJson,
    points,
    pointCount,
    minX,
    minY,
    maxX,
    maxY,
    recordingId,
    recordingOffsetMs,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    fieldVersions,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'strokes';
  @override
  VerificationContext validateIntegrity(
    Insertable<StrokeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('page_id')) {
      context.handle(
        _pageIdMeta,
        pageId.isAcceptableOrUnknown(data['page_id']!, _pageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_pageIdMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('tool')) {
      context.handle(
        _toolMeta,
        tool.isAcceptableOrUnknown(data['tool']!, _toolMeta),
      );
    } else if (isInserting) {
      context.missing(_toolMeta);
    }
    if (data.containsKey('color_argb')) {
      context.handle(
        _colorArgbMeta,
        colorArgb.isAcceptableOrUnknown(data['color_argb']!, _colorArgbMeta),
      );
    } else if (isInserting) {
      context.missing(_colorArgbMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    } else if (isInserting) {
      context.missing(_widthMeta);
    }
    if (data.containsKey('opacity')) {
      context.handle(
        _opacityMeta,
        opacity.isAcceptableOrUnknown(data['opacity']!, _opacityMeta),
      );
    } else if (isInserting) {
      context.missing(_opacityMeta);
    }
    if (data.containsKey('pressure_sensitivity')) {
      context.handle(
        _pressureSensitivityMeta,
        pressureSensitivity.isAcceptableOrUnknown(
          data['pressure_sensitivity']!,
          _pressureSensitivityMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_pressureSensitivityMeta);
    }
    if (data.containsKey('pressure_curve')) {
      context.handle(
        _pressureCurveMeta,
        pressureCurve.isAcceptableOrUnknown(
          data['pressure_curve']!,
          _pressureCurveMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_pressureCurveMeta);
    }
    if (data.containsKey('smoothing')) {
      context.handle(
        _smoothingMeta,
        smoothing.isAcceptableOrUnknown(data['smoothing']!, _smoothingMeta),
      );
    } else if (isInserting) {
      context.missing(_smoothingMeta);
    }
    if (data.containsKey('style_extras_json')) {
      context.handle(
        _styleExtrasJsonMeta,
        styleExtrasJson.isAcceptableOrUnknown(
          data['style_extras_json']!,
          _styleExtrasJsonMeta,
        ),
      );
    }
    if (data.containsKey('points')) {
      context.handle(
        _pointsMeta,
        points.isAcceptableOrUnknown(data['points']!, _pointsMeta),
      );
    } else if (isInserting) {
      context.missing(_pointsMeta);
    }
    if (data.containsKey('point_count')) {
      context.handle(
        _pointCountMeta,
        pointCount.isAcceptableOrUnknown(data['point_count']!, _pointCountMeta),
      );
    } else if (isInserting) {
      context.missing(_pointCountMeta);
    }
    if (data.containsKey('min_x')) {
      context.handle(
        _minXMeta,
        minX.isAcceptableOrUnknown(data['min_x']!, _minXMeta),
      );
    } else if (isInserting) {
      context.missing(_minXMeta);
    }
    if (data.containsKey('min_y')) {
      context.handle(
        _minYMeta,
        minY.isAcceptableOrUnknown(data['min_y']!, _minYMeta),
      );
    } else if (isInserting) {
      context.missing(_minYMeta);
    }
    if (data.containsKey('max_x')) {
      context.handle(
        _maxXMeta,
        maxX.isAcceptableOrUnknown(data['max_x']!, _maxXMeta),
      );
    } else if (isInserting) {
      context.missing(_maxXMeta);
    }
    if (data.containsKey('max_y')) {
      context.handle(
        _maxYMeta,
        maxY.isAcceptableOrUnknown(data['max_y']!, _maxYMeta),
      );
    } else if (isInserting) {
      context.missing(_maxYMeta);
    }
    if (data.containsKey('recording_id')) {
      context.handle(
        _recordingIdMeta,
        recordingId.isAcceptableOrUnknown(
          data['recording_id']!,
          _recordingIdMeta,
        ),
      );
    }
    if (data.containsKey('recording_offset_ms')) {
      context.handle(
        _recordingOffsetMsMeta,
        recordingOffsetMs.isAcceptableOrUnknown(
          data['recording_offset_ms']!,
          _recordingOffsetMsMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('field_versions')) {
      context.handle(
        _fieldVersionsMeta,
        fieldVersions.isAcceptableOrUnknown(
          data['field_versions']!,
          _fieldVersionsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StrokeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StrokeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      pageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}page_id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      tool: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tool'],
      )!,
      colorArgb: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_argb'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}width'],
      )!,
      opacity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}opacity'],
      )!,
      pressureSensitivity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pressure_sensitivity'],
      )!,
      pressureCurve: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pressure_curve'],
      )!,
      smoothing: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}smoothing'],
      )!,
      styleExtrasJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}style_extras_json'],
      ),
      points: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}points'],
      )!,
      pointCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}point_count'],
      )!,
      minX: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}min_x'],
      )!,
      minY: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}min_y'],
      )!,
      maxX: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_x'],
      )!,
      maxY: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_y'],
      )!,
      recordingId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recording_id'],
      ),
      recordingOffsetMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recording_offset_ms'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      fieldVersions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_versions'],
      ),
    );
  }

  @override
  $StrokesTable createAlias(String alias) {
    return $StrokesTable(attachedDatabase, alias);
  }
}

class StrokeRow extends DataClass implements Insertable<StrokeRow> {
  final String id;
  final String pageId;
  final String noteId;
  final String tool;
  final int colorArgb;
  final double width;
  final double opacity;
  final double pressureSensitivity;
  final String pressureCurve;
  final double smoothing;
  final String? styleExtrasJson;
  final Uint8List points;
  final int pointCount;
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;
  final String? recordingId;
  final int? recordingOffsetMs;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final String version;
  final String? fieldVersions;
  const StrokeRow({
    required this.id,
    required this.pageId,
    required this.noteId,
    required this.tool,
    required this.colorArgb,
    required this.width,
    required this.opacity,
    required this.pressureSensitivity,
    required this.pressureCurve,
    required this.smoothing,
    this.styleExtrasJson,
    required this.points,
    required this.pointCount,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    this.recordingId,
    this.recordingOffsetMs,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    this.fieldVersions,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['page_id'] = Variable<String>(pageId);
    map['note_id'] = Variable<String>(noteId);
    map['tool'] = Variable<String>(tool);
    map['color_argb'] = Variable<int>(colorArgb);
    map['width'] = Variable<double>(width);
    map['opacity'] = Variable<double>(opacity);
    map['pressure_sensitivity'] = Variable<double>(pressureSensitivity);
    map['pressure_curve'] = Variable<String>(pressureCurve);
    map['smoothing'] = Variable<double>(smoothing);
    if (!nullToAbsent || styleExtrasJson != null) {
      map['style_extras_json'] = Variable<String>(styleExtrasJson);
    }
    map['points'] = Variable<Uint8List>(points);
    map['point_count'] = Variable<int>(pointCount);
    map['min_x'] = Variable<double>(minX);
    map['min_y'] = Variable<double>(minY);
    map['max_x'] = Variable<double>(maxX);
    map['max_y'] = Variable<double>(maxY);
    if (!nullToAbsent || recordingId != null) {
      map['recording_id'] = Variable<String>(recordingId);
    }
    if (!nullToAbsent || recordingOffsetMs != null) {
      map['recording_offset_ms'] = Variable<int>(recordingOffsetMs);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<String>(version);
    if (!nullToAbsent || fieldVersions != null) {
      map['field_versions'] = Variable<String>(fieldVersions);
    }
    return map;
  }

  StrokesCompanion toCompanion(bool nullToAbsent) {
    return StrokesCompanion(
      id: Value(id),
      pageId: Value(pageId),
      noteId: Value(noteId),
      tool: Value(tool),
      colorArgb: Value(colorArgb),
      width: Value(width),
      opacity: Value(opacity),
      pressureSensitivity: Value(pressureSensitivity),
      pressureCurve: Value(pressureCurve),
      smoothing: Value(smoothing),
      styleExtrasJson: styleExtrasJson == null && nullToAbsent
          ? const Value.absent()
          : Value(styleExtrasJson),
      points: Value(points),
      pointCount: Value(pointCount),
      minX: Value(minX),
      minY: Value(minY),
      maxX: Value(maxX),
      maxY: Value(maxY),
      recordingId: recordingId == null && nullToAbsent
          ? const Value.absent()
          : Value(recordingId),
      recordingOffsetMs: recordingOffsetMs == null && nullToAbsent
          ? const Value.absent()
          : Value(recordingOffsetMs),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      fieldVersions: fieldVersions == null && nullToAbsent
          ? const Value.absent()
          : Value(fieldVersions),
    );
  }

  factory StrokeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StrokeRow(
      id: serializer.fromJson<String>(json['id']),
      pageId: serializer.fromJson<String>(json['pageId']),
      noteId: serializer.fromJson<String>(json['noteId']),
      tool: serializer.fromJson<String>(json['tool']),
      colorArgb: serializer.fromJson<int>(json['colorArgb']),
      width: serializer.fromJson<double>(json['width']),
      opacity: serializer.fromJson<double>(json['opacity']),
      pressureSensitivity: serializer.fromJson<double>(
        json['pressureSensitivity'],
      ),
      pressureCurve: serializer.fromJson<String>(json['pressureCurve']),
      smoothing: serializer.fromJson<double>(json['smoothing']),
      styleExtrasJson: serializer.fromJson<String?>(json['styleExtrasJson']),
      points: serializer.fromJson<Uint8List>(json['points']),
      pointCount: serializer.fromJson<int>(json['pointCount']),
      minX: serializer.fromJson<double>(json['minX']),
      minY: serializer.fromJson<double>(json['minY']),
      maxX: serializer.fromJson<double>(json['maxX']),
      maxY: serializer.fromJson<double>(json['maxY']),
      recordingId: serializer.fromJson<String?>(json['recordingId']),
      recordingOffsetMs: serializer.fromJson<int?>(json['recordingOffsetMs']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<String>(json['version']),
      fieldVersions: serializer.fromJson<String?>(json['fieldVersions']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'pageId': serializer.toJson<String>(pageId),
      'noteId': serializer.toJson<String>(noteId),
      'tool': serializer.toJson<String>(tool),
      'colorArgb': serializer.toJson<int>(colorArgb),
      'width': serializer.toJson<double>(width),
      'opacity': serializer.toJson<double>(opacity),
      'pressureSensitivity': serializer.toJson<double>(pressureSensitivity),
      'pressureCurve': serializer.toJson<String>(pressureCurve),
      'smoothing': serializer.toJson<double>(smoothing),
      'styleExtrasJson': serializer.toJson<String?>(styleExtrasJson),
      'points': serializer.toJson<Uint8List>(points),
      'pointCount': serializer.toJson<int>(pointCount),
      'minX': serializer.toJson<double>(minX),
      'minY': serializer.toJson<double>(minY),
      'maxX': serializer.toJson<double>(maxX),
      'maxY': serializer.toJson<double>(maxY),
      'recordingId': serializer.toJson<String?>(recordingId),
      'recordingOffsetMs': serializer.toJson<int?>(recordingOffsetMs),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<String>(version),
      'fieldVersions': serializer.toJson<String?>(fieldVersions),
    };
  }

  StrokeRow copyWith({
    String? id,
    String? pageId,
    String? noteId,
    String? tool,
    int? colorArgb,
    double? width,
    double? opacity,
    double? pressureSensitivity,
    String? pressureCurve,
    double? smoothing,
    Value<String?> styleExtrasJson = const Value.absent(),
    Uint8List? points,
    int? pointCount,
    double? minX,
    double? minY,
    double? maxX,
    double? maxY,
    Value<String?> recordingId = const Value.absent(),
    Value<int?> recordingOffsetMs = const Value.absent(),
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? version,
    Value<String?> fieldVersions = const Value.absent(),
  }) => StrokeRow(
    id: id ?? this.id,
    pageId: pageId ?? this.pageId,
    noteId: noteId ?? this.noteId,
    tool: tool ?? this.tool,
    colorArgb: colorArgb ?? this.colorArgb,
    width: width ?? this.width,
    opacity: opacity ?? this.opacity,
    pressureSensitivity: pressureSensitivity ?? this.pressureSensitivity,
    pressureCurve: pressureCurve ?? this.pressureCurve,
    smoothing: smoothing ?? this.smoothing,
    styleExtrasJson: styleExtrasJson.present
        ? styleExtrasJson.value
        : this.styleExtrasJson,
    points: points ?? this.points,
    pointCount: pointCount ?? this.pointCount,
    minX: minX ?? this.minX,
    minY: minY ?? this.minY,
    maxX: maxX ?? this.maxX,
    maxY: maxY ?? this.maxY,
    recordingId: recordingId.present ? recordingId.value : this.recordingId,
    recordingOffsetMs: recordingOffsetMs.present
        ? recordingOffsetMs.value
        : this.recordingOffsetMs,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    fieldVersions: fieldVersions.present
        ? fieldVersions.value
        : this.fieldVersions,
  );
  StrokeRow copyWithCompanion(StrokesCompanion data) {
    return StrokeRow(
      id: data.id.present ? data.id.value : this.id,
      pageId: data.pageId.present ? data.pageId.value : this.pageId,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      tool: data.tool.present ? data.tool.value : this.tool,
      colorArgb: data.colorArgb.present ? data.colorArgb.value : this.colorArgb,
      width: data.width.present ? data.width.value : this.width,
      opacity: data.opacity.present ? data.opacity.value : this.opacity,
      pressureSensitivity: data.pressureSensitivity.present
          ? data.pressureSensitivity.value
          : this.pressureSensitivity,
      pressureCurve: data.pressureCurve.present
          ? data.pressureCurve.value
          : this.pressureCurve,
      smoothing: data.smoothing.present ? data.smoothing.value : this.smoothing,
      styleExtrasJson: data.styleExtrasJson.present
          ? data.styleExtrasJson.value
          : this.styleExtrasJson,
      points: data.points.present ? data.points.value : this.points,
      pointCount: data.pointCount.present
          ? data.pointCount.value
          : this.pointCount,
      minX: data.minX.present ? data.minX.value : this.minX,
      minY: data.minY.present ? data.minY.value : this.minY,
      maxX: data.maxX.present ? data.maxX.value : this.maxX,
      maxY: data.maxY.present ? data.maxY.value : this.maxY,
      recordingId: data.recordingId.present
          ? data.recordingId.value
          : this.recordingId,
      recordingOffsetMs: data.recordingOffsetMs.present
          ? data.recordingOffsetMs.value
          : this.recordingOffsetMs,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      fieldVersions: data.fieldVersions.present
          ? data.fieldVersions.value
          : this.fieldVersions,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StrokeRow(')
          ..write('id: $id, ')
          ..write('pageId: $pageId, ')
          ..write('noteId: $noteId, ')
          ..write('tool: $tool, ')
          ..write('colorArgb: $colorArgb, ')
          ..write('width: $width, ')
          ..write('opacity: $opacity, ')
          ..write('pressureSensitivity: $pressureSensitivity, ')
          ..write('pressureCurve: $pressureCurve, ')
          ..write('smoothing: $smoothing, ')
          ..write('styleExtrasJson: $styleExtrasJson, ')
          ..write('points: $points, ')
          ..write('pointCount: $pointCount, ')
          ..write('minX: $minX, ')
          ..write('minY: $minY, ')
          ..write('maxX: $maxX, ')
          ..write('maxY: $maxY, ')
          ..write('recordingId: $recordingId, ')
          ..write('recordingOffsetMs: $recordingOffsetMs, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('fieldVersions: $fieldVersions')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    pageId,
    noteId,
    tool,
    colorArgb,
    width,
    opacity,
    pressureSensitivity,
    pressureCurve,
    smoothing,
    styleExtrasJson,
    $driftBlobEquality.hash(points),
    pointCount,
    minX,
    minY,
    maxX,
    maxY,
    recordingId,
    recordingOffsetMs,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    fieldVersions,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StrokeRow &&
          other.id == this.id &&
          other.pageId == this.pageId &&
          other.noteId == this.noteId &&
          other.tool == this.tool &&
          other.colorArgb == this.colorArgb &&
          other.width == this.width &&
          other.opacity == this.opacity &&
          other.pressureSensitivity == this.pressureSensitivity &&
          other.pressureCurve == this.pressureCurve &&
          other.smoothing == this.smoothing &&
          other.styleExtrasJson == this.styleExtrasJson &&
          $driftBlobEquality.equals(other.points, this.points) &&
          other.pointCount == this.pointCount &&
          other.minX == this.minX &&
          other.minY == this.minY &&
          other.maxX == this.maxX &&
          other.maxY == this.maxY &&
          other.recordingId == this.recordingId &&
          other.recordingOffsetMs == this.recordingOffsetMs &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.fieldVersions == this.fieldVersions);
}

class StrokesCompanion extends UpdateCompanion<StrokeRow> {
  final Value<String> id;
  final Value<String> pageId;
  final Value<String> noteId;
  final Value<String> tool;
  final Value<int> colorArgb;
  final Value<double> width;
  final Value<double> opacity;
  final Value<double> pressureSensitivity;
  final Value<String> pressureCurve;
  final Value<double> smoothing;
  final Value<String?> styleExtrasJson;
  final Value<Uint8List> points;
  final Value<int> pointCount;
  final Value<double> minX;
  final Value<double> minY;
  final Value<double> maxX;
  final Value<double> maxY;
  final Value<String?> recordingId;
  final Value<int?> recordingOffsetMs;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> version;
  final Value<String?> fieldVersions;
  final Value<int> rowid;
  const StrokesCompanion({
    this.id = const Value.absent(),
    this.pageId = const Value.absent(),
    this.noteId = const Value.absent(),
    this.tool = const Value.absent(),
    this.colorArgb = const Value.absent(),
    this.width = const Value.absent(),
    this.opacity = const Value.absent(),
    this.pressureSensitivity = const Value.absent(),
    this.pressureCurve = const Value.absent(),
    this.smoothing = const Value.absent(),
    this.styleExtrasJson = const Value.absent(),
    this.points = const Value.absent(),
    this.pointCount = const Value.absent(),
    this.minX = const Value.absent(),
    this.minY = const Value.absent(),
    this.maxX = const Value.absent(),
    this.maxY = const Value.absent(),
    this.recordingId = const Value.absent(),
    this.recordingOffsetMs = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.fieldVersions = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StrokesCompanion.insert({
    required String id,
    required String pageId,
    required String noteId,
    required String tool,
    required int colorArgb,
    required double width,
    required double opacity,
    required double pressureSensitivity,
    required String pressureCurve,
    required double smoothing,
    this.styleExtrasJson = const Value.absent(),
    required Uint8List points,
    required int pointCount,
    required double minX,
    required double minY,
    required double maxX,
    required double maxY,
    this.recordingId = const Value.absent(),
    this.recordingOffsetMs = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String version,
    this.fieldVersions = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       pageId = Value(pageId),
       noteId = Value(noteId),
       tool = Value(tool),
       colorArgb = Value(colorArgb),
       width = Value(width),
       opacity = Value(opacity),
       pressureSensitivity = Value(pressureSensitivity),
       pressureCurve = Value(pressureCurve),
       smoothing = Value(smoothing),
       points = Value(points),
       pointCount = Value(pointCount),
       minX = Value(minX),
       minY = Value(minY),
       maxX = Value(maxX),
       maxY = Value(maxY),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       version = Value(version);
  static Insertable<StrokeRow> custom({
    Expression<String>? id,
    Expression<String>? pageId,
    Expression<String>? noteId,
    Expression<String>? tool,
    Expression<int>? colorArgb,
    Expression<double>? width,
    Expression<double>? opacity,
    Expression<double>? pressureSensitivity,
    Expression<String>? pressureCurve,
    Expression<double>? smoothing,
    Expression<String>? styleExtrasJson,
    Expression<Uint8List>? points,
    Expression<int>? pointCount,
    Expression<double>? minX,
    Expression<double>? minY,
    Expression<double>? maxX,
    Expression<double>? maxY,
    Expression<String>? recordingId,
    Expression<int>? recordingOffsetMs,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? version,
    Expression<String>? fieldVersions,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pageId != null) 'page_id': pageId,
      if (noteId != null) 'note_id': noteId,
      if (tool != null) 'tool': tool,
      if (colorArgb != null) 'color_argb': colorArgb,
      if (width != null) 'width': width,
      if (opacity != null) 'opacity': opacity,
      if (pressureSensitivity != null)
        'pressure_sensitivity': pressureSensitivity,
      if (pressureCurve != null) 'pressure_curve': pressureCurve,
      if (smoothing != null) 'smoothing': smoothing,
      if (styleExtrasJson != null) 'style_extras_json': styleExtrasJson,
      if (points != null) 'points': points,
      if (pointCount != null) 'point_count': pointCount,
      if (minX != null) 'min_x': minX,
      if (minY != null) 'min_y': minY,
      if (maxX != null) 'max_x': maxX,
      if (maxY != null) 'max_y': maxY,
      if (recordingId != null) 'recording_id': recordingId,
      if (recordingOffsetMs != null) 'recording_offset_ms': recordingOffsetMs,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (fieldVersions != null) 'field_versions': fieldVersions,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StrokesCompanion copyWith({
    Value<String>? id,
    Value<String>? pageId,
    Value<String>? noteId,
    Value<String>? tool,
    Value<int>? colorArgb,
    Value<double>? width,
    Value<double>? opacity,
    Value<double>? pressureSensitivity,
    Value<String>? pressureCurve,
    Value<double>? smoothing,
    Value<String?>? styleExtrasJson,
    Value<Uint8List>? points,
    Value<int>? pointCount,
    Value<double>? minX,
    Value<double>? minY,
    Value<double>? maxX,
    Value<double>? maxY,
    Value<String?>? recordingId,
    Value<int?>? recordingOffsetMs,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? version,
    Value<String?>? fieldVersions,
    Value<int>? rowid,
  }) {
    return StrokesCompanion(
      id: id ?? this.id,
      pageId: pageId ?? this.pageId,
      noteId: noteId ?? this.noteId,
      tool: tool ?? this.tool,
      colorArgb: colorArgb ?? this.colorArgb,
      width: width ?? this.width,
      opacity: opacity ?? this.opacity,
      pressureSensitivity: pressureSensitivity ?? this.pressureSensitivity,
      pressureCurve: pressureCurve ?? this.pressureCurve,
      smoothing: smoothing ?? this.smoothing,
      styleExtrasJson: styleExtrasJson ?? this.styleExtrasJson,
      points: points ?? this.points,
      pointCount: pointCount ?? this.pointCount,
      minX: minX ?? this.minX,
      minY: minY ?? this.minY,
      maxX: maxX ?? this.maxX,
      maxY: maxY ?? this.maxY,
      recordingId: recordingId ?? this.recordingId,
      recordingOffsetMs: recordingOffsetMs ?? this.recordingOffsetMs,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      fieldVersions: fieldVersions ?? this.fieldVersions,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (pageId.present) {
      map['page_id'] = Variable<String>(pageId.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (tool.present) {
      map['tool'] = Variable<String>(tool.value);
    }
    if (colorArgb.present) {
      map['color_argb'] = Variable<int>(colorArgb.value);
    }
    if (width.present) {
      map['width'] = Variable<double>(width.value);
    }
    if (opacity.present) {
      map['opacity'] = Variable<double>(opacity.value);
    }
    if (pressureSensitivity.present) {
      map['pressure_sensitivity'] = Variable<double>(pressureSensitivity.value);
    }
    if (pressureCurve.present) {
      map['pressure_curve'] = Variable<String>(pressureCurve.value);
    }
    if (smoothing.present) {
      map['smoothing'] = Variable<double>(smoothing.value);
    }
    if (styleExtrasJson.present) {
      map['style_extras_json'] = Variable<String>(styleExtrasJson.value);
    }
    if (points.present) {
      map['points'] = Variable<Uint8List>(points.value);
    }
    if (pointCount.present) {
      map['point_count'] = Variable<int>(pointCount.value);
    }
    if (minX.present) {
      map['min_x'] = Variable<double>(minX.value);
    }
    if (minY.present) {
      map['min_y'] = Variable<double>(minY.value);
    }
    if (maxX.present) {
      map['max_x'] = Variable<double>(maxX.value);
    }
    if (maxY.present) {
      map['max_y'] = Variable<double>(maxY.value);
    }
    if (recordingId.present) {
      map['recording_id'] = Variable<String>(recordingId.value);
    }
    if (recordingOffsetMs.present) {
      map['recording_offset_ms'] = Variable<int>(recordingOffsetMs.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (fieldVersions.present) {
      map['field_versions'] = Variable<String>(fieldVersions.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StrokesCompanion(')
          ..write('id: $id, ')
          ..write('pageId: $pageId, ')
          ..write('noteId: $noteId, ')
          ..write('tool: $tool, ')
          ..write('colorArgb: $colorArgb, ')
          ..write('width: $width, ')
          ..write('opacity: $opacity, ')
          ..write('pressureSensitivity: $pressureSensitivity, ')
          ..write('pressureCurve: $pressureCurve, ')
          ..write('smoothing: $smoothing, ')
          ..write('styleExtrasJson: $styleExtrasJson, ')
          ..write('points: $points, ')
          ..write('pointCount: $pointCount, ')
          ..write('minX: $minX, ')
          ..write('minY: $minY, ')
          ..write('maxX: $maxX, ')
          ..write('maxY: $maxY, ')
          ..write('recordingId: $recordingId, ')
          ..write('recordingOffsetMs: $recordingOffsetMs, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('fieldVersions: $fieldVersions, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PenPresetsTable extends PenPresets
    with TableInfo<$PenPresetsTable, PenPresetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PenPresetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _styleJsonMeta = const VerificationMeta(
    'styleJson',
  );
  @override
  late final GeneratedColumn<String> styleJson = GeneratedColumn<String>(
    'style_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _groupNameMeta = const VerificationMeta(
    'groupName',
  );
  @override
  late final GeneratedColumn<String> groupName = GeneratedColumn<String>(
    'group_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
  );
  static const VerificationMeta _sortKeyMeta = const VerificationMeta(
    'sortKey',
  );
  @override
  late final GeneratedColumn<String> sortKey = GeneratedColumn<String>(
    'sort_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldVersionsMeta = const VerificationMeta(
    'fieldVersions',
  );
  @override
  late final GeneratedColumn<String> fieldVersions = GeneratedColumn<String>(
    'field_versions',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    name,
    styleJson,
    groupName,
    pinned,
    sortKey,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    fieldVersions,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pen_presets';
  @override
  VerificationContext validateIntegrity(
    Insertable<PenPresetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('style_json')) {
      context.handle(
        _styleJsonMeta,
        styleJson.isAcceptableOrUnknown(data['style_json']!, _styleJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_styleJsonMeta);
    }
    if (data.containsKey('group_name')) {
      context.handle(
        _groupNameMeta,
        groupName.isAcceptableOrUnknown(data['group_name']!, _groupNameMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    } else if (isInserting) {
      context.missing(_pinnedMeta);
    }
    if (data.containsKey('sort_key')) {
      context.handle(
        _sortKeyMeta,
        sortKey.isAcceptableOrUnknown(data['sort_key']!, _sortKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_sortKeyMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('field_versions')) {
      context.handle(
        _fieldVersionsMeta,
        fieldVersions.isAcceptableOrUnknown(
          data['field_versions']!,
          _fieldVersionsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PenPresetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PenPresetRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      styleJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}style_json'],
      )!,
      groupName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_name'],
      ),
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      sortKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sort_key'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      fieldVersions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_versions'],
      ),
    );
  }

  @override
  $PenPresetsTable createAlias(String alias) {
    return $PenPresetsTable(attachedDatabase, alias);
  }
}

class PenPresetRow extends DataClass implements Insertable<PenPresetRow> {
  final String id;
  final String ownerId;
  final String name;
  final String styleJson;
  final String? groupName;
  final bool pinned;
  final String sortKey;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final String version;
  final String? fieldVersions;
  const PenPresetRow({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.styleJson,
    this.groupName,
    required this.pinned,
    required this.sortKey,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    this.fieldVersions,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['name'] = Variable<String>(name);
    map['style_json'] = Variable<String>(styleJson);
    if (!nullToAbsent || groupName != null) {
      map['group_name'] = Variable<String>(groupName);
    }
    map['pinned'] = Variable<bool>(pinned);
    map['sort_key'] = Variable<String>(sortKey);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<String>(version);
    if (!nullToAbsent || fieldVersions != null) {
      map['field_versions'] = Variable<String>(fieldVersions);
    }
    return map;
  }

  PenPresetsCompanion toCompanion(bool nullToAbsent) {
    return PenPresetsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      name: Value(name),
      styleJson: Value(styleJson),
      groupName: groupName == null && nullToAbsent
          ? const Value.absent()
          : Value(groupName),
      pinned: Value(pinned),
      sortKey: Value(sortKey),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      fieldVersions: fieldVersions == null && nullToAbsent
          ? const Value.absent()
          : Value(fieldVersions),
    );
  }

  factory PenPresetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PenPresetRow(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      name: serializer.fromJson<String>(json['name']),
      styleJson: serializer.fromJson<String>(json['styleJson']),
      groupName: serializer.fromJson<String?>(json['groupName']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      sortKey: serializer.fromJson<String>(json['sortKey']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<String>(json['version']),
      fieldVersions: serializer.fromJson<String?>(json['fieldVersions']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'name': serializer.toJson<String>(name),
      'styleJson': serializer.toJson<String>(styleJson),
      'groupName': serializer.toJson<String?>(groupName),
      'pinned': serializer.toJson<bool>(pinned),
      'sortKey': serializer.toJson<String>(sortKey),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<String>(version),
      'fieldVersions': serializer.toJson<String?>(fieldVersions),
    };
  }

  PenPresetRow copyWith({
    String? id,
    String? ownerId,
    String? name,
    String? styleJson,
    Value<String?> groupName = const Value.absent(),
    bool? pinned,
    String? sortKey,
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? version,
    Value<String?> fieldVersions = const Value.absent(),
  }) => PenPresetRow(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    name: name ?? this.name,
    styleJson: styleJson ?? this.styleJson,
    groupName: groupName.present ? groupName.value : this.groupName,
    pinned: pinned ?? this.pinned,
    sortKey: sortKey ?? this.sortKey,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    fieldVersions: fieldVersions.present
        ? fieldVersions.value
        : this.fieldVersions,
  );
  PenPresetRow copyWithCompanion(PenPresetsCompanion data) {
    return PenPresetRow(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      name: data.name.present ? data.name.value : this.name,
      styleJson: data.styleJson.present ? data.styleJson.value : this.styleJson,
      groupName: data.groupName.present ? data.groupName.value : this.groupName,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      sortKey: data.sortKey.present ? data.sortKey.value : this.sortKey,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      fieldVersions: data.fieldVersions.present
          ? data.fieldVersions.value
          : this.fieldVersions,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PenPresetRow(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('name: $name, ')
          ..write('styleJson: $styleJson, ')
          ..write('groupName: $groupName, ')
          ..write('pinned: $pinned, ')
          ..write('sortKey: $sortKey, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('fieldVersions: $fieldVersions')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    name,
    styleJson,
    groupName,
    pinned,
    sortKey,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    fieldVersions,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PenPresetRow &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.name == this.name &&
          other.styleJson == this.styleJson &&
          other.groupName == this.groupName &&
          other.pinned == this.pinned &&
          other.sortKey == this.sortKey &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.fieldVersions == this.fieldVersions);
}

class PenPresetsCompanion extends UpdateCompanion<PenPresetRow> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> name;
  final Value<String> styleJson;
  final Value<String?> groupName;
  final Value<bool> pinned;
  final Value<String> sortKey;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> version;
  final Value<String?> fieldVersions;
  final Value<int> rowid;
  const PenPresetsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.name = const Value.absent(),
    this.styleJson = const Value.absent(),
    this.groupName = const Value.absent(),
    this.pinned = const Value.absent(),
    this.sortKey = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.fieldVersions = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PenPresetsCompanion.insert({
    required String id,
    required String ownerId,
    required String name,
    required String styleJson,
    this.groupName = const Value.absent(),
    required bool pinned,
    required String sortKey,
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String version,
    this.fieldVersions = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       name = Value(name),
       styleJson = Value(styleJson),
       pinned = Value(pinned),
       sortKey = Value(sortKey),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       version = Value(version);
  static Insertable<PenPresetRow> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? name,
    Expression<String>? styleJson,
    Expression<String>? groupName,
    Expression<bool>? pinned,
    Expression<String>? sortKey,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? version,
    Expression<String>? fieldVersions,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (name != null) 'name': name,
      if (styleJson != null) 'style_json': styleJson,
      if (groupName != null) 'group_name': groupName,
      if (pinned != null) 'pinned': pinned,
      if (sortKey != null) 'sort_key': sortKey,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (fieldVersions != null) 'field_versions': fieldVersions,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PenPresetsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? name,
    Value<String>? styleJson,
    Value<String?>? groupName,
    Value<bool>? pinned,
    Value<String>? sortKey,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? version,
    Value<String?>? fieldVersions,
    Value<int>? rowid,
  }) {
    return PenPresetsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      styleJson: styleJson ?? this.styleJson,
      groupName: groupName ?? this.groupName,
      pinned: pinned ?? this.pinned,
      sortKey: sortKey ?? this.sortKey,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      fieldVersions: fieldVersions ?? this.fieldVersions,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (styleJson.present) {
      map['style_json'] = Variable<String>(styleJson.value);
    }
    if (groupName.present) {
      map['group_name'] = Variable<String>(groupName.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (sortKey.present) {
      map['sort_key'] = Variable<String>(sortKey.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (fieldVersions.present) {
      map['field_versions'] = Variable<String>(fieldVersions.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PenPresetsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('name: $name, ')
          ..write('styleJson: $styleJson, ')
          ..write('groupName: $groupName, ')
          ..write('pinned: $pinned, ')
          ..write('sortKey: $sortKey, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('fieldVersions: $fieldVersions, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssetsTable extends Assets with TableInfo<$AssetsTable, AssetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _chunkCountMeta = const VerificationMeta(
    'chunkCount',
  );
  @override
  late final GeneratedColumn<int> chunkCount = GeneratedColumn<int>(
    'chunk_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hasLocalBytesMeta = const VerificationMeta(
    'hasLocalBytes',
  );
  @override
  late final GeneratedColumn<bool> hasLocalBytes = GeneratedColumn<bool>(
    'has_local_bytes',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_local_bytes" IN (0, 1))',
    ),
  );
  static const VerificationMeta _storagePathMeta = const VerificationMeta(
    'storagePath',
  );
  @override
  late final GeneratedColumn<String> storagePath = GeneratedColumn<String>(
    'storage_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldVersionsMeta = const VerificationMeta(
    'fieldVersions',
  );
  @override
  late final GeneratedColumn<String> fieldVersions = GeneratedColumn<String>(
    'field_versions',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    type,
    mimeType,
    size,
    fileName,
    chunkCount,
    hasLocalBytes,
    storagePath,
    createdAt,
    deletedAt,
    version,
    fieldVersions,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    }
    if (data.containsKey('chunk_count')) {
      context.handle(
        _chunkCountMeta,
        chunkCount.isAcceptableOrUnknown(data['chunk_count']!, _chunkCountMeta),
      );
    } else if (isInserting) {
      context.missing(_chunkCountMeta);
    }
    if (data.containsKey('has_local_bytes')) {
      context.handle(
        _hasLocalBytesMeta,
        hasLocalBytes.isAcceptableOrUnknown(
          data['has_local_bytes']!,
          _hasLocalBytesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_hasLocalBytesMeta);
    }
    if (data.containsKey('storage_path')) {
      context.handle(
        _storagePathMeta,
        storagePath.isAcceptableOrUnknown(
          data['storage_path']!,
          _storagePathMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('field_versions')) {
      context.handle(
        _fieldVersionsMeta,
        fieldVersions.isAcceptableOrUnknown(
          data['field_versions']!,
          _fieldVersionsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AssetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssetRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      ),
      chunkCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chunk_count'],
      )!,
      hasLocalBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_local_bytes'],
      )!,
      storagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}storage_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      fieldVersions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_versions'],
      ),
    );
  }

  @override
  $AssetsTable createAlias(String alias) {
    return $AssetsTable(attachedDatabase, alias);
  }
}

class AssetRow extends DataClass implements Insertable<AssetRow> {
  final String id;
  final String ownerId;
  final String type;
  final String mimeType;
  final int size;
  final String? fileName;
  final int chunkCount;
  final bool hasLocalBytes;
  final String? storagePath;
  final int createdAt;
  final int? deletedAt;
  final String version;
  final String? fieldVersions;
  const AssetRow({
    required this.id,
    required this.ownerId,
    required this.type,
    required this.mimeType,
    required this.size,
    this.fileName,
    required this.chunkCount,
    required this.hasLocalBytes,
    this.storagePath,
    required this.createdAt,
    this.deletedAt,
    required this.version,
    this.fieldVersions,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['type'] = Variable<String>(type);
    map['mime_type'] = Variable<String>(mimeType);
    map['size'] = Variable<int>(size);
    if (!nullToAbsent || fileName != null) {
      map['file_name'] = Variable<String>(fileName);
    }
    map['chunk_count'] = Variable<int>(chunkCount);
    map['has_local_bytes'] = Variable<bool>(hasLocalBytes);
    if (!nullToAbsent || storagePath != null) {
      map['storage_path'] = Variable<String>(storagePath);
    }
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<String>(version);
    if (!nullToAbsent || fieldVersions != null) {
      map['field_versions'] = Variable<String>(fieldVersions);
    }
    return map;
  }

  AssetsCompanion toCompanion(bool nullToAbsent) {
    return AssetsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      type: Value(type),
      mimeType: Value(mimeType),
      size: Value(size),
      fileName: fileName == null && nullToAbsent
          ? const Value.absent()
          : Value(fileName),
      chunkCount: Value(chunkCount),
      hasLocalBytes: Value(hasLocalBytes),
      storagePath: storagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(storagePath),
      createdAt: Value(createdAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      fieldVersions: fieldVersions == null && nullToAbsent
          ? const Value.absent()
          : Value(fieldVersions),
    );
  }

  factory AssetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssetRow(
      id: serializer.fromJson<String>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      type: serializer.fromJson<String>(json['type']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      size: serializer.fromJson<int>(json['size']),
      fileName: serializer.fromJson<String?>(json['fileName']),
      chunkCount: serializer.fromJson<int>(json['chunkCount']),
      hasLocalBytes: serializer.fromJson<bool>(json['hasLocalBytes']),
      storagePath: serializer.fromJson<String?>(json['storagePath']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<String>(json['version']),
      fieldVersions: serializer.fromJson<String?>(json['fieldVersions']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'type': serializer.toJson<String>(type),
      'mimeType': serializer.toJson<String>(mimeType),
      'size': serializer.toJson<int>(size),
      'fileName': serializer.toJson<String?>(fileName),
      'chunkCount': serializer.toJson<int>(chunkCount),
      'hasLocalBytes': serializer.toJson<bool>(hasLocalBytes),
      'storagePath': serializer.toJson<String?>(storagePath),
      'createdAt': serializer.toJson<int>(createdAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<String>(version),
      'fieldVersions': serializer.toJson<String?>(fieldVersions),
    };
  }

  AssetRow copyWith({
    String? id,
    String? ownerId,
    String? type,
    String? mimeType,
    int? size,
    Value<String?> fileName = const Value.absent(),
    int? chunkCount,
    bool? hasLocalBytes,
    Value<String?> storagePath = const Value.absent(),
    int? createdAt,
    Value<int?> deletedAt = const Value.absent(),
    String? version,
    Value<String?> fieldVersions = const Value.absent(),
  }) => AssetRow(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    type: type ?? this.type,
    mimeType: mimeType ?? this.mimeType,
    size: size ?? this.size,
    fileName: fileName.present ? fileName.value : this.fileName,
    chunkCount: chunkCount ?? this.chunkCount,
    hasLocalBytes: hasLocalBytes ?? this.hasLocalBytes,
    storagePath: storagePath.present ? storagePath.value : this.storagePath,
    createdAt: createdAt ?? this.createdAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    fieldVersions: fieldVersions.present
        ? fieldVersions.value
        : this.fieldVersions,
  );
  AssetRow copyWithCompanion(AssetsCompanion data) {
    return AssetRow(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      type: data.type.present ? data.type.value : this.type,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      size: data.size.present ? data.size.value : this.size,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      chunkCount: data.chunkCount.present
          ? data.chunkCount.value
          : this.chunkCount,
      hasLocalBytes: data.hasLocalBytes.present
          ? data.hasLocalBytes.value
          : this.hasLocalBytes,
      storagePath: data.storagePath.present
          ? data.storagePath.value
          : this.storagePath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      fieldVersions: data.fieldVersions.present
          ? data.fieldVersions.value
          : this.fieldVersions,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssetRow(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('type: $type, ')
          ..write('mimeType: $mimeType, ')
          ..write('size: $size, ')
          ..write('fileName: $fileName, ')
          ..write('chunkCount: $chunkCount, ')
          ..write('hasLocalBytes: $hasLocalBytes, ')
          ..write('storagePath: $storagePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('fieldVersions: $fieldVersions')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    type,
    mimeType,
    size,
    fileName,
    chunkCount,
    hasLocalBytes,
    storagePath,
    createdAt,
    deletedAt,
    version,
    fieldVersions,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssetRow &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.type == this.type &&
          other.mimeType == this.mimeType &&
          other.size == this.size &&
          other.fileName == this.fileName &&
          other.chunkCount == this.chunkCount &&
          other.hasLocalBytes == this.hasLocalBytes &&
          other.storagePath == this.storagePath &&
          other.createdAt == this.createdAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.fieldVersions == this.fieldVersions);
}

class AssetsCompanion extends UpdateCompanion<AssetRow> {
  final Value<String> id;
  final Value<String> ownerId;
  final Value<String> type;
  final Value<String> mimeType;
  final Value<int> size;
  final Value<String?> fileName;
  final Value<int> chunkCount;
  final Value<bool> hasLocalBytes;
  final Value<String?> storagePath;
  final Value<int> createdAt;
  final Value<int?> deletedAt;
  final Value<String> version;
  final Value<String?> fieldVersions;
  final Value<int> rowid;
  const AssetsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.type = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.size = const Value.absent(),
    this.fileName = const Value.absent(),
    this.chunkCount = const Value.absent(),
    this.hasLocalBytes = const Value.absent(),
    this.storagePath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.fieldVersions = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssetsCompanion.insert({
    required String id,
    required String ownerId,
    required String type,
    required String mimeType,
    required int size,
    this.fileName = const Value.absent(),
    required int chunkCount,
    required bool hasLocalBytes,
    this.storagePath = const Value.absent(),
    required int createdAt,
    this.deletedAt = const Value.absent(),
    required String version,
    this.fieldVersions = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerId = Value(ownerId),
       type = Value(type),
       mimeType = Value(mimeType),
       size = Value(size),
       chunkCount = Value(chunkCount),
       hasLocalBytes = Value(hasLocalBytes),
       createdAt = Value(createdAt),
       version = Value(version);
  static Insertable<AssetRow> custom({
    Expression<String>? id,
    Expression<String>? ownerId,
    Expression<String>? type,
    Expression<String>? mimeType,
    Expression<int>? size,
    Expression<String>? fileName,
    Expression<int>? chunkCount,
    Expression<bool>? hasLocalBytes,
    Expression<String>? storagePath,
    Expression<int>? createdAt,
    Expression<int>? deletedAt,
    Expression<String>? version,
    Expression<String>? fieldVersions,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (type != null) 'type': type,
      if (mimeType != null) 'mime_type': mimeType,
      if (size != null) 'size': size,
      if (fileName != null) 'file_name': fileName,
      if (chunkCount != null) 'chunk_count': chunkCount,
      if (hasLocalBytes != null) 'has_local_bytes': hasLocalBytes,
      if (storagePath != null) 'storage_path': storagePath,
      if (createdAt != null) 'created_at': createdAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (fieldVersions != null) 'field_versions': fieldVersions,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssetsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerId,
    Value<String>? type,
    Value<String>? mimeType,
    Value<int>? size,
    Value<String?>? fileName,
    Value<int>? chunkCount,
    Value<bool>? hasLocalBytes,
    Value<String?>? storagePath,
    Value<int>? createdAt,
    Value<int?>? deletedAt,
    Value<String>? version,
    Value<String?>? fieldVersions,
    Value<int>? rowid,
  }) {
    return AssetsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      type: type ?? this.type,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      fileName: fileName ?? this.fileName,
      chunkCount: chunkCount ?? this.chunkCount,
      hasLocalBytes: hasLocalBytes ?? this.hasLocalBytes,
      storagePath: storagePath ?? this.storagePath,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      fieldVersions: fieldVersions ?? this.fieldVersions,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (chunkCount.present) {
      map['chunk_count'] = Variable<int>(chunkCount.value);
    }
    if (hasLocalBytes.present) {
      map['has_local_bytes'] = Variable<bool>(hasLocalBytes.value);
    }
    if (storagePath.present) {
      map['storage_path'] = Variable<String>(storagePath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (fieldVersions.present) {
      map['field_versions'] = Variable<String>(fieldVersions.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssetsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('type: $type, ')
          ..write('mimeType: $mimeType, ')
          ..write('size: $size, ')
          ..write('fileName: $fileName, ')
          ..write('chunkCount: $chunkCount, ')
          ..write('hasLocalBytes: $hasLocalBytes, ')
          ..write('storagePath: $storagePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('fieldVersions: $fieldVersions, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecordingsTable extends Recordings
    with TableInfo<$RecordingsTable, RecordingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecordingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldVersionsMeta = const VerificationMeta(
    'fieldVersions',
  );
  @override
  late final GeneratedColumn<String> fieldVersions = GeneratedColumn<String>(
    'field_versions',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    noteId,
    assetId,
    durationMs,
    startedAt,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    fieldVersions,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recordings';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecordingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('field_versions')) {
      context.handle(
        _fieldVersionsMeta,
        fieldVersions.isAcceptableOrUnknown(
          data['field_versions']!,
          _fieldVersionsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecordingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecordingRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      fieldVersions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_versions'],
      ),
    );
  }

  @override
  $RecordingsTable createAlias(String alias) {
    return $RecordingsTable(attachedDatabase, alias);
  }
}

class RecordingRow extends DataClass implements Insertable<RecordingRow> {
  final String id;
  final String noteId;
  final String assetId;
  final int durationMs;
  final int startedAt;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final String version;
  final String? fieldVersions;
  const RecordingRow({
    required this.id,
    required this.noteId,
    required this.assetId,
    required this.durationMs,
    required this.startedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    this.fieldVersions,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['note_id'] = Variable<String>(noteId);
    map['asset_id'] = Variable<String>(assetId);
    map['duration_ms'] = Variable<int>(durationMs);
    map['started_at'] = Variable<int>(startedAt);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<String>(version);
    if (!nullToAbsent || fieldVersions != null) {
      map['field_versions'] = Variable<String>(fieldVersions);
    }
    return map;
  }

  RecordingsCompanion toCompanion(bool nullToAbsent) {
    return RecordingsCompanion(
      id: Value(id),
      noteId: Value(noteId),
      assetId: Value(assetId),
      durationMs: Value(durationMs),
      startedAt: Value(startedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      fieldVersions: fieldVersions == null && nullToAbsent
          ? const Value.absent()
          : Value(fieldVersions),
    );
  }

  factory RecordingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecordingRow(
      id: serializer.fromJson<String>(json['id']),
      noteId: serializer.fromJson<String>(json['noteId']),
      assetId: serializer.fromJson<String>(json['assetId']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      startedAt: serializer.fromJson<int>(json['startedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<String>(json['version']),
      fieldVersions: serializer.fromJson<String?>(json['fieldVersions']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'noteId': serializer.toJson<String>(noteId),
      'assetId': serializer.toJson<String>(assetId),
      'durationMs': serializer.toJson<int>(durationMs),
      'startedAt': serializer.toJson<int>(startedAt),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<String>(version),
      'fieldVersions': serializer.toJson<String?>(fieldVersions),
    };
  }

  RecordingRow copyWith({
    String? id,
    String? noteId,
    String? assetId,
    int? durationMs,
    int? startedAt,
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? version,
    Value<String?> fieldVersions = const Value.absent(),
  }) => RecordingRow(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    assetId: assetId ?? this.assetId,
    durationMs: durationMs ?? this.durationMs,
    startedAt: startedAt ?? this.startedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    fieldVersions: fieldVersions.present
        ? fieldVersions.value
        : this.fieldVersions,
  );
  RecordingRow copyWithCompanion(RecordingsCompanion data) {
    return RecordingRow(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      fieldVersions: data.fieldVersions.present
          ? data.fieldVersions.value
          : this.fieldVersions,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecordingRow(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('assetId: $assetId, ')
          ..write('durationMs: $durationMs, ')
          ..write('startedAt: $startedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('fieldVersions: $fieldVersions')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    noteId,
    assetId,
    durationMs,
    startedAt,
    createdAt,
    updatedAt,
    deletedAt,
    version,
    fieldVersions,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecordingRow &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.assetId == this.assetId &&
          other.durationMs == this.durationMs &&
          other.startedAt == this.startedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.fieldVersions == this.fieldVersions);
}

class RecordingsCompanion extends UpdateCompanion<RecordingRow> {
  final Value<String> id;
  final Value<String> noteId;
  final Value<String> assetId;
  final Value<int> durationMs;
  final Value<int> startedAt;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> version;
  final Value<String?> fieldVersions;
  final Value<int> rowid;
  const RecordingsCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.assetId = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.fieldVersions = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecordingsCompanion.insert({
    required String id,
    required String noteId,
    required String assetId,
    required int durationMs,
    required int startedAt,
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String version,
    this.fieldVersions = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       noteId = Value(noteId),
       assetId = Value(assetId),
       durationMs = Value(durationMs),
       startedAt = Value(startedAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       version = Value(version);
  static Insertable<RecordingRow> custom({
    Expression<String>? id,
    Expression<String>? noteId,
    Expression<String>? assetId,
    Expression<int>? durationMs,
    Expression<int>? startedAt,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? version,
    Expression<String>? fieldVersions,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (assetId != null) 'asset_id': assetId,
      if (durationMs != null) 'duration_ms': durationMs,
      if (startedAt != null) 'started_at': startedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (fieldVersions != null) 'field_versions': fieldVersions,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecordingsCompanion copyWith({
    Value<String>? id,
    Value<String>? noteId,
    Value<String>? assetId,
    Value<int>? durationMs,
    Value<int>? startedAt,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? version,
    Value<String?>? fieldVersions,
    Value<int>? rowid,
  }) {
    return RecordingsCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      assetId: assetId ?? this.assetId,
      durationMs: durationMs ?? this.durationMs,
      startedAt: startedAt ?? this.startedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      fieldVersions: fieldVersions ?? this.fieldVersions,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (fieldVersions.present) {
      map['field_versions'] = Variable<String>(fieldVersions.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecordingsCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('assetId: $assetId, ')
          ..write('durationMs: $durationMs, ')
          ..write('startedAt: $startedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('fieldVersions: $fieldVersions, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldVersionsMeta = const VerificationMeta(
    'fieldVersions',
  );
  @override
  late final GeneratedColumn<String> fieldVersions = GeneratedColumn<String>(
    'field_versions',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    key,
    valueJson,
    updatedAt,
    deletedAt,
    version,
    fieldVersions,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_valueJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('field_versions')) {
      context.handle(
        _fieldVersionsMeta,
        fieldVersions.isAcceptableOrUnknown(
          data['field_versions']!,
          _fieldVersionsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      fieldVersions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_versions'],
      ),
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String valueJson;
  final int updatedAt;
  final int? deletedAt;
  final String version;
  final String? fieldVersions;
  const SettingRow({
    required this.key,
    required this.valueJson,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
    this.fieldVersions,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value_json'] = Variable<String>(valueJson);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['version'] = Variable<String>(version);
    if (!nullToAbsent || fieldVersions != null) {
      map['field_versions'] = Variable<String>(fieldVersions);
    }
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      key: Value(key),
      valueJson: Value(valueJson),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      version: Value(version),
      fieldVersions: fieldVersions == null && nullToAbsent
          ? const Value.absent()
          : Value(fieldVersions),
    );
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      valueJson: serializer.fromJson<String>(json['valueJson']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      version: serializer.fromJson<String>(json['version']),
      fieldVersions: serializer.fromJson<String?>(json['fieldVersions']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'valueJson': serializer.toJson<String>(valueJson),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'version': serializer.toJson<String>(version),
      'fieldVersions': serializer.toJson<String?>(fieldVersions),
    };
  }

  SettingRow copyWith({
    String? key,
    String? valueJson,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? version,
    Value<String?> fieldVersions = const Value.absent(),
  }) => SettingRow(
    key: key ?? this.key,
    valueJson: valueJson ?? this.valueJson,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    version: version ?? this.version,
    fieldVersions: fieldVersions.present
        ? fieldVersions.value
        : this.fieldVersions,
  );
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      version: data.version.present ? data.version.value : this.version,
      fieldVersions: data.fieldVersions.present
          ? data.fieldVersions.value
          : this.fieldVersions,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('fieldVersions: $fieldVersions')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(key, valueJson, updatedAt, deletedAt, version, fieldVersions);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.valueJson == this.valueJson &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.version == this.version &&
          other.fieldVersions == this.fieldVersions);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> valueJson;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> version;
  final Value<String?> fieldVersions;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.fieldVersions = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String valueJson,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String version,
    this.fieldVersions = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       valueJson = Value(valueJson),
       updatedAt = Value(updatedAt),
       version = Value(version);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? valueJson,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? version,
    Expression<String>? fieldVersions,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (valueJson != null) 'value_json': valueJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (version != null) 'version': version,
      if (fieldVersions != null) 'field_versions': fieldVersions,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? valueJson,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? version,
    Value<String?>? fieldVersions,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      valueJson: valueJson ?? this.valueJson,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      version: version ?? this.version,
      fieldVersions: fieldVersions ?? this.fieldVersions,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (fieldVersions.present) {
      map['field_versions'] = Variable<String>(fieldVersions.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('version: $version, ')
          ..write('fieldVersions: $fieldVersions, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _revMeta = const VerificationMeta('rev');
  @override
  late final GeneratedColumn<int> rev = GeneratedColumn<int>(
    'rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityKindMeta = const VerificationMeta(
    'entityKind',
  );
  @override
  late final GeneratedColumn<String> entityKind = GeneratedColumn<String>(
    'entity_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageIdMeta = const VerificationMeta('pageId');
  @override
  late final GeneratedColumn<String> pageId = GeneratedColumn<String>(
    'page_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _opMeta = const VerificationMeta('op');
  @override
  late final GeneratedColumn<String> op = GeneratedColumn<String>(
    'op',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _changedFieldsMeta = const VerificationMeta(
    'changedFields',
  );
  @override
  late final GeneratedColumn<String> changedFields = GeneratedColumn<String>(
    'changed_fields',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enqueuedAtMeta = const VerificationMeta(
    'enqueuedAt',
  );
  @override
  late final GeneratedColumn<int> enqueuedAt = GeneratedColumn<int>(
    'enqueued_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    seq,
    rev,
    entityKind,
    entityId,
    noteId,
    pageId,
    op,
    changedFields,
    hlc,
    enqueuedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    }
    if (data.containsKey('rev')) {
      context.handle(
        _revMeta,
        rev.isAcceptableOrUnknown(data['rev']!, _revMeta),
      );
    } else if (isInserting) {
      context.missing(_revMeta);
    }
    if (data.containsKey('entity_kind')) {
      context.handle(
        _entityKindMeta,
        entityKind.isAcceptableOrUnknown(data['entity_kind']!, _entityKindMeta),
      );
    } else if (isInserting) {
      context.missing(_entityKindMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    }
    if (data.containsKey('page_id')) {
      context.handle(
        _pageIdMeta,
        pageId.isAcceptableOrUnknown(data['page_id']!, _pageIdMeta),
      );
    }
    if (data.containsKey('op')) {
      context.handle(_opMeta, op.isAcceptableOrUnknown(data['op']!, _opMeta));
    } else if (isInserting) {
      context.missing(_opMeta);
    }
    if (data.containsKey('changed_fields')) {
      context.handle(
        _changedFieldsMeta,
        changedFields.isAcceptableOrUnknown(
          data['changed_fields']!,
          _changedFieldsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_changedFieldsMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('enqueued_at')) {
      context.handle(
        _enqueuedAtMeta,
        enqueuedAt.isAcceptableOrUnknown(data['enqueued_at']!, _enqueuedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_enqueuedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seq};
  @override
  OutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxRow(
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      rev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rev'],
      )!,
      entityKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_kind'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      ),
      pageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}page_id'],
      ),
      op: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op'],
      )!,
      changedFields: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}changed_fields'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      enqueuedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}enqueued_at'],
      )!,
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class OutboxRow extends DataClass implements Insertable<OutboxRow> {
  final int seq;
  final int rev;
  final String entityKind;
  final String entityId;
  final String? noteId;
  final String? pageId;
  final String op;
  final String changedFields;
  final String hlc;
  final int enqueuedAt;
  const OutboxRow({
    required this.seq,
    required this.rev,
    required this.entityKind,
    required this.entityId,
    this.noteId,
    this.pageId,
    required this.op,
    required this.changedFields,
    required this.hlc,
    required this.enqueuedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['seq'] = Variable<int>(seq);
    map['rev'] = Variable<int>(rev);
    map['entity_kind'] = Variable<String>(entityKind);
    map['entity_id'] = Variable<String>(entityId);
    if (!nullToAbsent || noteId != null) {
      map['note_id'] = Variable<String>(noteId);
    }
    if (!nullToAbsent || pageId != null) {
      map['page_id'] = Variable<String>(pageId);
    }
    map['op'] = Variable<String>(op);
    map['changed_fields'] = Variable<String>(changedFields);
    map['hlc'] = Variable<String>(hlc);
    map['enqueued_at'] = Variable<int>(enqueuedAt);
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      seq: Value(seq),
      rev: Value(rev),
      entityKind: Value(entityKind),
      entityId: Value(entityId),
      noteId: noteId == null && nullToAbsent
          ? const Value.absent()
          : Value(noteId),
      pageId: pageId == null && nullToAbsent
          ? const Value.absent()
          : Value(pageId),
      op: Value(op),
      changedFields: Value(changedFields),
      hlc: Value(hlc),
      enqueuedAt: Value(enqueuedAt),
    );
  }

  factory OutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxRow(
      seq: serializer.fromJson<int>(json['seq']),
      rev: serializer.fromJson<int>(json['rev']),
      entityKind: serializer.fromJson<String>(json['entityKind']),
      entityId: serializer.fromJson<String>(json['entityId']),
      noteId: serializer.fromJson<String?>(json['noteId']),
      pageId: serializer.fromJson<String?>(json['pageId']),
      op: serializer.fromJson<String>(json['op']),
      changedFields: serializer.fromJson<String>(json['changedFields']),
      hlc: serializer.fromJson<String>(json['hlc']),
      enqueuedAt: serializer.fromJson<int>(json['enqueuedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seq': serializer.toJson<int>(seq),
      'rev': serializer.toJson<int>(rev),
      'entityKind': serializer.toJson<String>(entityKind),
      'entityId': serializer.toJson<String>(entityId),
      'noteId': serializer.toJson<String?>(noteId),
      'pageId': serializer.toJson<String?>(pageId),
      'op': serializer.toJson<String>(op),
      'changedFields': serializer.toJson<String>(changedFields),
      'hlc': serializer.toJson<String>(hlc),
      'enqueuedAt': serializer.toJson<int>(enqueuedAt),
    };
  }

  OutboxRow copyWith({
    int? seq,
    int? rev,
    String? entityKind,
    String? entityId,
    Value<String?> noteId = const Value.absent(),
    Value<String?> pageId = const Value.absent(),
    String? op,
    String? changedFields,
    String? hlc,
    int? enqueuedAt,
  }) => OutboxRow(
    seq: seq ?? this.seq,
    rev: rev ?? this.rev,
    entityKind: entityKind ?? this.entityKind,
    entityId: entityId ?? this.entityId,
    noteId: noteId.present ? noteId.value : this.noteId,
    pageId: pageId.present ? pageId.value : this.pageId,
    op: op ?? this.op,
    changedFields: changedFields ?? this.changedFields,
    hlc: hlc ?? this.hlc,
    enqueuedAt: enqueuedAt ?? this.enqueuedAt,
  );
  OutboxRow copyWithCompanion(OutboxCompanion data) {
    return OutboxRow(
      seq: data.seq.present ? data.seq.value : this.seq,
      rev: data.rev.present ? data.rev.value : this.rev,
      entityKind: data.entityKind.present
          ? data.entityKind.value
          : this.entityKind,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      pageId: data.pageId.present ? data.pageId.value : this.pageId,
      op: data.op.present ? data.op.value : this.op,
      changedFields: data.changedFields.present
          ? data.changedFields.value
          : this.changedFields,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      enqueuedAt: data.enqueuedAt.present
          ? data.enqueuedAt.value
          : this.enqueuedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRow(')
          ..write('seq: $seq, ')
          ..write('rev: $rev, ')
          ..write('entityKind: $entityKind, ')
          ..write('entityId: $entityId, ')
          ..write('noteId: $noteId, ')
          ..write('pageId: $pageId, ')
          ..write('op: $op, ')
          ..write('changedFields: $changedFields, ')
          ..write('hlc: $hlc, ')
          ..write('enqueuedAt: $enqueuedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    seq,
    rev,
    entityKind,
    entityId,
    noteId,
    pageId,
    op,
    changedFields,
    hlc,
    enqueuedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxRow &&
          other.seq == this.seq &&
          other.rev == this.rev &&
          other.entityKind == this.entityKind &&
          other.entityId == this.entityId &&
          other.noteId == this.noteId &&
          other.pageId == this.pageId &&
          other.op == this.op &&
          other.changedFields == this.changedFields &&
          other.hlc == this.hlc &&
          other.enqueuedAt == this.enqueuedAt);
}

class OutboxCompanion extends UpdateCompanion<OutboxRow> {
  final Value<int> seq;
  final Value<int> rev;
  final Value<String> entityKind;
  final Value<String> entityId;
  final Value<String?> noteId;
  final Value<String?> pageId;
  final Value<String> op;
  final Value<String> changedFields;
  final Value<String> hlc;
  final Value<int> enqueuedAt;
  const OutboxCompanion({
    this.seq = const Value.absent(),
    this.rev = const Value.absent(),
    this.entityKind = const Value.absent(),
    this.entityId = const Value.absent(),
    this.noteId = const Value.absent(),
    this.pageId = const Value.absent(),
    this.op = const Value.absent(),
    this.changedFields = const Value.absent(),
    this.hlc = const Value.absent(),
    this.enqueuedAt = const Value.absent(),
  });
  OutboxCompanion.insert({
    this.seq = const Value.absent(),
    required int rev,
    required String entityKind,
    required String entityId,
    this.noteId = const Value.absent(),
    this.pageId = const Value.absent(),
    required String op,
    required String changedFields,
    required String hlc,
    required int enqueuedAt,
  }) : rev = Value(rev),
       entityKind = Value(entityKind),
       entityId = Value(entityId),
       op = Value(op),
       changedFields = Value(changedFields),
       hlc = Value(hlc),
       enqueuedAt = Value(enqueuedAt);
  static Insertable<OutboxRow> custom({
    Expression<int>? seq,
    Expression<int>? rev,
    Expression<String>? entityKind,
    Expression<String>? entityId,
    Expression<String>? noteId,
    Expression<String>? pageId,
    Expression<String>? op,
    Expression<String>? changedFields,
    Expression<String>? hlc,
    Expression<int>? enqueuedAt,
  }) {
    return RawValuesInsertable({
      if (seq != null) 'seq': seq,
      if (rev != null) 'rev': rev,
      if (entityKind != null) 'entity_kind': entityKind,
      if (entityId != null) 'entity_id': entityId,
      if (noteId != null) 'note_id': noteId,
      if (pageId != null) 'page_id': pageId,
      if (op != null) 'op': op,
      if (changedFields != null) 'changed_fields': changedFields,
      if (hlc != null) 'hlc': hlc,
      if (enqueuedAt != null) 'enqueued_at': enqueuedAt,
    });
  }

  OutboxCompanion copyWith({
    Value<int>? seq,
    Value<int>? rev,
    Value<String>? entityKind,
    Value<String>? entityId,
    Value<String?>? noteId,
    Value<String?>? pageId,
    Value<String>? op,
    Value<String>? changedFields,
    Value<String>? hlc,
    Value<int>? enqueuedAt,
  }) {
    return OutboxCompanion(
      seq: seq ?? this.seq,
      rev: rev ?? this.rev,
      entityKind: entityKind ?? this.entityKind,
      entityId: entityId ?? this.entityId,
      noteId: noteId ?? this.noteId,
      pageId: pageId ?? this.pageId,
      op: op ?? this.op,
      changedFields: changedFields ?? this.changedFields,
      hlc: hlc ?? this.hlc,
      enqueuedAt: enqueuedAt ?? this.enqueuedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (rev.present) {
      map['rev'] = Variable<int>(rev.value);
    }
    if (entityKind.present) {
      map['entity_kind'] = Variable<String>(entityKind.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (pageId.present) {
      map['page_id'] = Variable<String>(pageId.value);
    }
    if (op.present) {
      map['op'] = Variable<String>(op.value);
    }
    if (changedFields.present) {
      map['changed_fields'] = Variable<String>(changedFields.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (enqueuedAt.present) {
      map['enqueued_at'] = Variable<int>(enqueuedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('seq: $seq, ')
          ..write('rev: $rev, ')
          ..write('entityKind: $entityKind, ')
          ..write('entityId: $entityId, ')
          ..write('noteId: $noteId, ')
          ..write('pageId: $pageId, ')
          ..write('op: $op, ')
          ..write('changedFields: $changedFields, ')
          ..write('hlc: $hlc, ')
          ..write('enqueuedAt: $enqueuedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$NoteDatabase extends GeneratedDatabase {
  _$NoteDatabase(QueryExecutor e) : super(e);
  $NoteDatabaseManager get managers => $NoteDatabaseManager(this);
  late final $KvTable kv = $KvTable(this);
  late final $FoldersTable folders = $FoldersTable(this);
  late final $NotesTable notes = $NotesTable(this);
  late final $PagesTable pages = $PagesTable(this);
  late final $StrokesTable strokes = $StrokesTable(this);
  late final $PenPresetsTable penPresets = $PenPresetsTable(this);
  late final $AssetsTable assets = $AssetsTable(this);
  late final $RecordingsTable recordings = $RecordingsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final Index idxFoldersParent = Index(
    'idx_folders_parent',
    'CREATE INDEX idx_folders_parent ON folders (owner_id, parent_id, deleted_at)',
  );
  late final Index idxFoldersTrash = Index(
    'idx_folders_trash',
    'CREATE INDEX idx_folders_trash ON folders (trash_root_id)',
  );
  late final Index idxNotesFolder = Index(
    'idx_notes_folder',
    'CREATE INDEX idx_notes_folder ON notes (owner_id, folder_id, deleted_at)',
  );
  late final Index idxNotesOpened = Index(
    'idx_notes_opened',
    'CREATE INDEX idx_notes_opened ON notes (owner_id, last_opened_at)',
  );
  late final Index idxNotesFavorite = Index(
    'idx_notes_favorite',
    'CREATE INDEX idx_notes_favorite ON notes (owner_id, is_favorite, deleted_at)',
  );
  late final Index idxNotesTrash = Index(
    'idx_notes_trash',
    'CREATE INDEX idx_notes_trash ON notes (trash_root_id)',
  );
  late final Index idxPagesNote = Index(
    'idx_pages_note',
    'CREATE INDEX idx_pages_note ON pages (note_id, deleted_at, sort_key)',
  );
  late final Index idxStrokesPage = Index(
    'idx_strokes_page',
    'CREATE INDEX idx_strokes_page ON strokes (page_id, deleted_at)',
  );
  late final Index idxStrokesNote = Index(
    'idx_strokes_note',
    'CREATE INDEX idx_strokes_note ON strokes (note_id)',
  );
  late final Index idxStrokesRecording = Index(
    'idx_strokes_recording',
    'CREATE INDEX idx_strokes_recording ON strokes (recording_id)',
  );
  late final Index idxOutboxEntity = Index(
    'idx_outbox_entity',
    'CREATE UNIQUE INDEX idx_outbox_entity ON outbox (entity_kind, entity_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    kv,
    folders,
    notes,
    pages,
    strokes,
    penPresets,
    assets,
    recordings,
    settings,
    outbox,
    idxFoldersParent,
    idxFoldersTrash,
    idxNotesFolder,
    idxNotesOpened,
    idxNotesFavorite,
    idxNotesTrash,
    idxPagesNote,
    idxStrokesPage,
    idxStrokesNote,
    idxStrokesRecording,
    idxOutboxEntity,
  ];
}

typedef $$KvTableCreateCompanionBuilder = KvCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$KvTableUpdateCompanionBuilder = KvCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$KvTableFilterComposer extends Composer<_$NoteDatabase, $KvTable> {
  $$KvTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KvTableOrderingComposer extends Composer<_$NoteDatabase, $KvTable> {
  $$KvTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KvTableAnnotationComposer extends Composer<_$NoteDatabase, $KvTable> {
  $$KvTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$KvTableTableManager
    extends
        RootTableManager<
          _$NoteDatabase,
          $KvTable,
          KvRow,
          $$KvTableFilterComposer,
          $$KvTableOrderingComposer,
          $$KvTableAnnotationComposer,
          $$KvTableCreateCompanionBuilder,
          $$KvTableUpdateCompanionBuilder,
          (KvRow, BaseReferences<_$NoteDatabase, $KvTable, KvRow>),
          KvRow,
          PrefetchHooks Function()
        > {
  $$KvTableTableManager(_$NoteDatabase db, $KvTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KvTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KvTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KvTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => KvCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => KvCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KvTable, KvRow>(table),
                  BaseReferences<_$NoteDatabase, $KvTable, KvRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KvTableProcessedTableManager =
    ProcessedTableManager<
      _$NoteDatabase,
      $KvTable,
      KvRow,
      $$KvTableFilterComposer,
      $$KvTableOrderingComposer,
      $$KvTableAnnotationComposer,
      $$KvTableCreateCompanionBuilder,
      $$KvTableUpdateCompanionBuilder,
      (KvRow, BaseReferences<_$NoteDatabase, $KvTable, KvRow>),
      KvRow,
      PrefetchHooks Function()
    >;
typedef $$FoldersTableCreateCompanionBuilder = FoldersCompanion Function({
  required String id,
  required String ownerId,
  Value<String?> parentId,
  required String name,
  required String nameNorm,
  Value<int?> colorArgb,
  Value<String?> icon,
  required String sortKey,
  required int createdAt,
  required int updatedAt,
  Value<int?> deletedAt,
  Value<String?> trashRootId,
  required String version,
  Value<String?> fieldVersions,
  Value<int> rowid,
});
typedef $$FoldersTableUpdateCompanionBuilder = FoldersCompanion Function({
  Value<String> id,
  Value<String> ownerId,
  Value<String?> parentId,
  Value<String> name,
  Value<String> nameNorm,
  Value<int?> colorArgb,
  Value<String?> icon,
  Value<String> sortKey,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int?> deletedAt,
  Value<String?> trashRootId,
  Value<String> version,
  Value<String?> fieldVersions,
  Value<int> rowid,
});

class $$FoldersTableFilterComposer
    extends Composer<_$NoteDatabase, $FoldersTable> {
  $$FoldersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameNorm => $composableBuilder(
    column: $table.nameNorm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorArgb => $composableBuilder(
    column: $table.colorArgb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trashRootId => $composableBuilder(
    column: $table.trashRootId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FoldersTableOrderingComposer
    extends Composer<_$NoteDatabase, $FoldersTable> {
  $$FoldersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameNorm => $composableBuilder(
    column: $table.nameNorm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorArgb => $composableBuilder(
    column: $table.colorArgb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trashRootId => $composableBuilder(
    column: $table.trashRootId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FoldersTableAnnotationComposer
    extends Composer<_$NoteDatabase, $FoldersTable> {
  $$FoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameNorm =>
      $composableBuilder(column: $table.nameNorm, builder: (column) => column);

  GeneratedColumn<int> get colorArgb =>
      $composableBuilder(column: $table.colorArgb, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get sortKey =>
      $composableBuilder(column: $table.sortKey, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get trashRootId => $composableBuilder(
    column: $table.trashRootId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => column,
  );
}

class $$FoldersTableTableManager
    extends
        RootTableManager<
          _$NoteDatabase,
          $FoldersTable,
          FolderRow,
          $$FoldersTableFilterComposer,
          $$FoldersTableOrderingComposer,
          $$FoldersTableAnnotationComposer,
          $$FoldersTableCreateCompanionBuilder,
          $$FoldersTableUpdateCompanionBuilder,
          (FolderRow, BaseReferences<_$NoteDatabase, $FoldersTable, FolderRow>),
          FolderRow,
          PrefetchHooks Function()
        > {
  $$FoldersTableTableManager(_$NoteDatabase db, $FoldersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> nameNorm = const Value.absent(),
                Value<int?> colorArgb = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                Value<String> sortKey = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String?> trashRootId = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String?> fieldVersions = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoldersCompanion(
                id: id,
                ownerId: ownerId,
                parentId: parentId,
                name: name,
                nameNorm: nameNorm,
                colorArgb: colorArgb,
                icon: icon,
                sortKey: sortKey,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                trashRootId: trashRootId,
                version: version,
                fieldVersions: fieldVersions,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                Value<String?> parentId = const Value.absent(),
                required String name,
                required String nameNorm,
                Value<int?> colorArgb = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                required String sortKey,
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<String?> trashRootId = const Value.absent(),
                required String version,
                Value<String?> fieldVersions = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoldersCompanion.insert(
                id: id,
                ownerId: ownerId,
                parentId: parentId,
                name: name,
                nameNorm: nameNorm,
                colorArgb: colorArgb,
                icon: icon,
                sortKey: sortKey,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                trashRootId: trashRootId,
                version: version,
                fieldVersions: fieldVersions,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FoldersTable, FolderRow>(table),
                  BaseReferences<_$NoteDatabase, $FoldersTable, FolderRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FoldersTableProcessedTableManager =
    ProcessedTableManager<
      _$NoteDatabase,
      $FoldersTable,
      FolderRow,
      $$FoldersTableFilterComposer,
      $$FoldersTableOrderingComposer,
      $$FoldersTableAnnotationComposer,
      $$FoldersTableCreateCompanionBuilder,
      $$FoldersTableUpdateCompanionBuilder,
      (FolderRow, BaseReferences<_$NoteDatabase, $FoldersTable, FolderRow>),
      FolderRow,
      PrefetchHooks Function()
    >;
typedef $$NotesTableCreateCompanionBuilder = NotesCompanion Function({
  required String id,
  required String ownerId,
  Value<String?> folderId,
  required String title,
  required String titleNorm,
  required String coverJson,
  required String tagsJson,
  required bool isFavorite,
  required String sortKey,
  required int schemaVersion,
  required int createdAt,
  required int updatedAt,
  Value<int?> deletedAt,
  Value<String?> trashRootId,
  required String version,
  Value<String?> fieldVersions,
  required int pageCount,
  Value<String?> firstPageId,
  Value<int?> lastOpenedAt,
  Value<int> rowid,
});
typedef $$NotesTableUpdateCompanionBuilder = NotesCompanion Function({
  Value<String> id,
  Value<String> ownerId,
  Value<String?> folderId,
  Value<String> title,
  Value<String> titleNorm,
  Value<String> coverJson,
  Value<String> tagsJson,
  Value<bool> isFavorite,
  Value<String> sortKey,
  Value<int> schemaVersion,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int?> deletedAt,
  Value<String?> trashRootId,
  Value<String> version,
  Value<String?> fieldVersions,
  Value<int> pageCount,
  Value<String?> firstPageId,
  Value<int?> lastOpenedAt,
  Value<int> rowid,
});

class $$NotesTableFilterComposer extends Composer<_$NoteDatabase, $NotesTable> {
  $$NotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get titleNorm => $composableBuilder(
    column: $table.titleNorm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverJson => $composableBuilder(
    column: $table.coverJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trashRootId => $composableBuilder(
    column: $table.trashRootId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstPageId => $composableBuilder(
    column: $table.firstPageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotesTableOrderingComposer
    extends Composer<_$NoteDatabase, $NotesTable> {
  $$NotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get titleNorm => $composableBuilder(
    column: $table.titleNorm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverJson => $composableBuilder(
    column: $table.coverJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trashRootId => $composableBuilder(
    column: $table.trashRootId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstPageId => $composableBuilder(
    column: $table.firstPageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotesTableAnnotationComposer
    extends Composer<_$NoteDatabase, $NotesTable> {
  $$NotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get folderId =>
      $composableBuilder(column: $table.folderId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get titleNorm =>
      $composableBuilder(column: $table.titleNorm, builder: (column) => column);

  GeneratedColumn<String> get coverJson =>
      $composableBuilder(column: $table.coverJson, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sortKey =>
      $composableBuilder(column: $table.sortKey, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get trashRootId => $composableBuilder(
    column: $table.trashRootId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pageCount =>
      $composableBuilder(column: $table.pageCount, builder: (column) => column);

  GeneratedColumn<String> get firstPageId => $composableBuilder(
    column: $table.firstPageId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => column,
  );
}

class $$NotesTableTableManager
    extends
        RootTableManager<
          _$NoteDatabase,
          $NotesTable,
          NoteRow,
          $$NotesTableFilterComposer,
          $$NotesTableOrderingComposer,
          $$NotesTableAnnotationComposer,
          $$NotesTableCreateCompanionBuilder,
          $$NotesTableUpdateCompanionBuilder,
          (NoteRow, BaseReferences<_$NoteDatabase, $NotesTable, NoteRow>),
          NoteRow,
          PrefetchHooks Function()
        > {
  $$NotesTableTableManager(_$NoteDatabase db, $NotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String?> folderId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> titleNorm = const Value.absent(),
                Value<String> coverJson = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<String> sortKey = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String?> trashRootId = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String?> fieldVersions = const Value.absent(),
                Value<int> pageCount = const Value.absent(),
                Value<String?> firstPageId = const Value.absent(),
                Value<int?> lastOpenedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion(
                id: id,
                ownerId: ownerId,
                folderId: folderId,
                title: title,
                titleNorm: titleNorm,
                coverJson: coverJson,
                tagsJson: tagsJson,
                isFavorite: isFavorite,
                sortKey: sortKey,
                schemaVersion: schemaVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                trashRootId: trashRootId,
                version: version,
                fieldVersions: fieldVersions,
                pageCount: pageCount,
                firstPageId: firstPageId,
                lastOpenedAt: lastOpenedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                Value<String?> folderId = const Value.absent(),
                required String title,
                required String titleNorm,
                required String coverJson,
                required String tagsJson,
                required bool isFavorite,
                required String sortKey,
                required int schemaVersion,
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<String?> trashRootId = const Value.absent(),
                required String version,
                Value<String?> fieldVersions = const Value.absent(),
                required int pageCount,
                Value<String?> firstPageId = const Value.absent(),
                Value<int?> lastOpenedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion.insert(
                id: id,
                ownerId: ownerId,
                folderId: folderId,
                title: title,
                titleNorm: titleNorm,
                coverJson: coverJson,
                tagsJson: tagsJson,
                isFavorite: isFavorite,
                sortKey: sortKey,
                schemaVersion: schemaVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                trashRootId: trashRootId,
                version: version,
                fieldVersions: fieldVersions,
                pageCount: pageCount,
                firstPageId: firstPageId,
                lastOpenedAt: lastOpenedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$NotesTable, NoteRow>(table),
                  BaseReferences<_$NoteDatabase, $NotesTable, NoteRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotesTableProcessedTableManager =
    ProcessedTableManager<
      _$NoteDatabase,
      $NotesTable,
      NoteRow,
      $$NotesTableFilterComposer,
      $$NotesTableOrderingComposer,
      $$NotesTableAnnotationComposer,
      $$NotesTableCreateCompanionBuilder,
      $$NotesTableUpdateCompanionBuilder,
      (NoteRow, BaseReferences<_$NoteDatabase, $NotesTable, NoteRow>),
      NoteRow,
      PrefetchHooks Function()
    >;
typedef $$PagesTableCreateCompanionBuilder = PagesCompanion Function({
  required String id,
  required String noteId,
  required String sortKey,
  required double width,
  required double height,
  required String backgroundJson,
  required int createdAt,
  required int updatedAt,
  Value<int?> deletedAt,
  required String version,
  Value<String?> fieldVersions,
  required int contentRev,
  Value<int> rowid,
});
typedef $$PagesTableUpdateCompanionBuilder = PagesCompanion Function({
  Value<String> id,
  Value<String> noteId,
  Value<String> sortKey,
  Value<double> width,
  Value<double> height,
  Value<String> backgroundJson,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int?> deletedAt,
  Value<String> version,
  Value<String?> fieldVersions,
  Value<int> contentRev,
  Value<int> rowid,
});

class $$PagesTableFilterComposer extends Composer<_$NoteDatabase, $PagesTable> {
  $$PagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backgroundJson => $composableBuilder(
    column: $table.backgroundJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get contentRev => $composableBuilder(
    column: $table.contentRev,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PagesTableOrderingComposer
    extends Composer<_$NoteDatabase, $PagesTable> {
  $$PagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backgroundJson => $composableBuilder(
    column: $table.backgroundJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get contentRev => $composableBuilder(
    column: $table.contentRev,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PagesTableAnnotationComposer
    extends Composer<_$NoteDatabase, $PagesTable> {
  $$PagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get sortKey =>
      $composableBuilder(column: $table.sortKey, builder: (column) => column);

  GeneratedColumn<double> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<double> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<String> get backgroundJson => $composableBuilder(
    column: $table.backgroundJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => column,
  );

  GeneratedColumn<int> get contentRev => $composableBuilder(
    column: $table.contentRev,
    builder: (column) => column,
  );
}

class $$PagesTableTableManager
    extends
        RootTableManager<
          _$NoteDatabase,
          $PagesTable,
          PageRow,
          $$PagesTableFilterComposer,
          $$PagesTableOrderingComposer,
          $$PagesTableAnnotationComposer,
          $$PagesTableCreateCompanionBuilder,
          $$PagesTableUpdateCompanionBuilder,
          (PageRow, BaseReferences<_$NoteDatabase, $PagesTable, PageRow>),
          PageRow,
          PrefetchHooks Function()
        > {
  $$PagesTableTableManager(_$NoteDatabase db, $PagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<String> sortKey = const Value.absent(),
                Value<double> width = const Value.absent(),
                Value<double> height = const Value.absent(),
                Value<String> backgroundJson = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String?> fieldVersions = const Value.absent(),
                Value<int> contentRev = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PagesCompanion(
                id: id,
                noteId: noteId,
                sortKey: sortKey,
                width: width,
                height: height,
                backgroundJson: backgroundJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                fieldVersions: fieldVersions,
                contentRev: contentRev,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String noteId,
                required String sortKey,
                required double width,
                required double height,
                required String backgroundJson,
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String version,
                Value<String?> fieldVersions = const Value.absent(),
                required int contentRev,
                Value<int> rowid = const Value.absent(),
              }) => PagesCompanion.insert(
                id: id,
                noteId: noteId,
                sortKey: sortKey,
                width: width,
                height: height,
                backgroundJson: backgroundJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                fieldVersions: fieldVersions,
                contentRev: contentRev,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PagesTable, PageRow>(table),
                  BaseReferences<_$NoteDatabase, $PagesTable, PageRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PagesTableProcessedTableManager =
    ProcessedTableManager<
      _$NoteDatabase,
      $PagesTable,
      PageRow,
      $$PagesTableFilterComposer,
      $$PagesTableOrderingComposer,
      $$PagesTableAnnotationComposer,
      $$PagesTableCreateCompanionBuilder,
      $$PagesTableUpdateCompanionBuilder,
      (PageRow, BaseReferences<_$NoteDatabase, $PagesTable, PageRow>),
      PageRow,
      PrefetchHooks Function()
    >;
typedef $$StrokesTableCreateCompanionBuilder = StrokesCompanion Function({
  required String id,
  required String pageId,
  required String noteId,
  required String tool,
  required int colorArgb,
  required double width,
  required double opacity,
  required double pressureSensitivity,
  required String pressureCurve,
  required double smoothing,
  Value<String?> styleExtrasJson,
  required Uint8List points,
  required int pointCount,
  required double minX,
  required double minY,
  required double maxX,
  required double maxY,
  Value<String?> recordingId,
  Value<int?> recordingOffsetMs,
  required int createdAt,
  required int updatedAt,
  Value<int?> deletedAt,
  required String version,
  Value<String?> fieldVersions,
  Value<int> rowid,
});
typedef $$StrokesTableUpdateCompanionBuilder = StrokesCompanion Function({
  Value<String> id,
  Value<String> pageId,
  Value<String> noteId,
  Value<String> tool,
  Value<int> colorArgb,
  Value<double> width,
  Value<double> opacity,
  Value<double> pressureSensitivity,
  Value<String> pressureCurve,
  Value<double> smoothing,
  Value<String?> styleExtrasJson,
  Value<Uint8List> points,
  Value<int> pointCount,
  Value<double> minX,
  Value<double> minY,
  Value<double> maxX,
  Value<double> maxY,
  Value<String?> recordingId,
  Value<int?> recordingOffsetMs,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int?> deletedAt,
  Value<String> version,
  Value<String?> fieldVersions,
  Value<int> rowid,
});

class $$StrokesTableFilterComposer
    extends Composer<_$NoteDatabase, $StrokesTable> {
  $$StrokesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tool => $composableBuilder(
    column: $table.tool,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorArgb => $composableBuilder(
    column: $table.colorArgb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get opacity => $composableBuilder(
    column: $table.opacity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pressureSensitivity => $composableBuilder(
    column: $table.pressureSensitivity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pressureCurve => $composableBuilder(
    column: $table.pressureCurve,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get smoothing => $composableBuilder(
    column: $table.smoothing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get styleExtrasJson => $composableBuilder(
    column: $table.styleExtrasJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get points => $composableBuilder(
    column: $table.points,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pointCount => $composableBuilder(
    column: $table.pointCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get minX => $composableBuilder(
    column: $table.minX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get minY => $composableBuilder(
    column: $table.minY,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get maxX => $composableBuilder(
    column: $table.maxX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get maxY => $composableBuilder(
    column: $table.maxY,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordingId => $composableBuilder(
    column: $table.recordingId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recordingOffsetMs => $composableBuilder(
    column: $table.recordingOffsetMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StrokesTableOrderingComposer
    extends Composer<_$NoteDatabase, $StrokesTable> {
  $$StrokesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tool => $composableBuilder(
    column: $table.tool,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorArgb => $composableBuilder(
    column: $table.colorArgb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get opacity => $composableBuilder(
    column: $table.opacity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pressureSensitivity => $composableBuilder(
    column: $table.pressureSensitivity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pressureCurve => $composableBuilder(
    column: $table.pressureCurve,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get smoothing => $composableBuilder(
    column: $table.smoothing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get styleExtrasJson => $composableBuilder(
    column: $table.styleExtrasJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get points => $composableBuilder(
    column: $table.points,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pointCount => $composableBuilder(
    column: $table.pointCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get minX => $composableBuilder(
    column: $table.minX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get minY => $composableBuilder(
    column: $table.minY,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get maxX => $composableBuilder(
    column: $table.maxX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get maxY => $composableBuilder(
    column: $table.maxY,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordingId => $composableBuilder(
    column: $table.recordingId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recordingOffsetMs => $composableBuilder(
    column: $table.recordingOffsetMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StrokesTableAnnotationComposer
    extends Composer<_$NoteDatabase, $StrokesTable> {
  $$StrokesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get pageId =>
      $composableBuilder(column: $table.pageId, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get tool =>
      $composableBuilder(column: $table.tool, builder: (column) => column);

  GeneratedColumn<int> get colorArgb =>
      $composableBuilder(column: $table.colorArgb, builder: (column) => column);

  GeneratedColumn<double> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<double> get opacity =>
      $composableBuilder(column: $table.opacity, builder: (column) => column);

  GeneratedColumn<double> get pressureSensitivity => $composableBuilder(
    column: $table.pressureSensitivity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pressureCurve => $composableBuilder(
    column: $table.pressureCurve,
    builder: (column) => column,
  );

  GeneratedColumn<double> get smoothing =>
      $composableBuilder(column: $table.smoothing, builder: (column) => column);

  GeneratedColumn<String> get styleExtrasJson => $composableBuilder(
    column: $table.styleExtrasJson,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get points =>
      $composableBuilder(column: $table.points, builder: (column) => column);

  GeneratedColumn<int> get pointCount => $composableBuilder(
    column: $table.pointCount,
    builder: (column) => column,
  );

  GeneratedColumn<double> get minX =>
      $composableBuilder(column: $table.minX, builder: (column) => column);

  GeneratedColumn<double> get minY =>
      $composableBuilder(column: $table.minY, builder: (column) => column);

  GeneratedColumn<double> get maxX =>
      $composableBuilder(column: $table.maxX, builder: (column) => column);

  GeneratedColumn<double> get maxY =>
      $composableBuilder(column: $table.maxY, builder: (column) => column);

  GeneratedColumn<String> get recordingId => $composableBuilder(
    column: $table.recordingId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recordingOffsetMs => $composableBuilder(
    column: $table.recordingOffsetMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => column,
  );
}

class $$StrokesTableTableManager
    extends
        RootTableManager<
          _$NoteDatabase,
          $StrokesTable,
          StrokeRow,
          $$StrokesTableFilterComposer,
          $$StrokesTableOrderingComposer,
          $$StrokesTableAnnotationComposer,
          $$StrokesTableCreateCompanionBuilder,
          $$StrokesTableUpdateCompanionBuilder,
          (StrokeRow, BaseReferences<_$NoteDatabase, $StrokesTable, StrokeRow>),
          StrokeRow,
          PrefetchHooks Function()
        > {
  $$StrokesTableTableManager(_$NoteDatabase db, $StrokesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StrokesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StrokesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StrokesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> pageId = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<String> tool = const Value.absent(),
                Value<int> colorArgb = const Value.absent(),
                Value<double> width = const Value.absent(),
                Value<double> opacity = const Value.absent(),
                Value<double> pressureSensitivity = const Value.absent(),
                Value<String> pressureCurve = const Value.absent(),
                Value<double> smoothing = const Value.absent(),
                Value<String?> styleExtrasJson = const Value.absent(),
                Value<Uint8List> points = const Value.absent(),
                Value<int> pointCount = const Value.absent(),
                Value<double> minX = const Value.absent(),
                Value<double> minY = const Value.absent(),
                Value<double> maxX = const Value.absent(),
                Value<double> maxY = const Value.absent(),
                Value<String?> recordingId = const Value.absent(),
                Value<int?> recordingOffsetMs = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String?> fieldVersions = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StrokesCompanion(
                id: id,
                pageId: pageId,
                noteId: noteId,
                tool: tool,
                colorArgb: colorArgb,
                width: width,
                opacity: opacity,
                pressureSensitivity: pressureSensitivity,
                pressureCurve: pressureCurve,
                smoothing: smoothing,
                styleExtrasJson: styleExtrasJson,
                points: points,
                pointCount: pointCount,
                minX: minX,
                minY: minY,
                maxX: maxX,
                maxY: maxY,
                recordingId: recordingId,
                recordingOffsetMs: recordingOffsetMs,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                fieldVersions: fieldVersions,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String pageId,
                required String noteId,
                required String tool,
                required int colorArgb,
                required double width,
                required double opacity,
                required double pressureSensitivity,
                required String pressureCurve,
                required double smoothing,
                Value<String?> styleExtrasJson = const Value.absent(),
                required Uint8List points,
                required int pointCount,
                required double minX,
                required double minY,
                required double maxX,
                required double maxY,
                Value<String?> recordingId = const Value.absent(),
                Value<int?> recordingOffsetMs = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String version,
                Value<String?> fieldVersions = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StrokesCompanion.insert(
                id: id,
                pageId: pageId,
                noteId: noteId,
                tool: tool,
                colorArgb: colorArgb,
                width: width,
                opacity: opacity,
                pressureSensitivity: pressureSensitivity,
                pressureCurve: pressureCurve,
                smoothing: smoothing,
                styleExtrasJson: styleExtrasJson,
                points: points,
                pointCount: pointCount,
                minX: minX,
                minY: minY,
                maxX: maxX,
                maxY: maxY,
                recordingId: recordingId,
                recordingOffsetMs: recordingOffsetMs,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                fieldVersions: fieldVersions,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StrokesTable, StrokeRow>(table),
                  BaseReferences<_$NoteDatabase, $StrokesTable, StrokeRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StrokesTableProcessedTableManager =
    ProcessedTableManager<
      _$NoteDatabase,
      $StrokesTable,
      StrokeRow,
      $$StrokesTableFilterComposer,
      $$StrokesTableOrderingComposer,
      $$StrokesTableAnnotationComposer,
      $$StrokesTableCreateCompanionBuilder,
      $$StrokesTableUpdateCompanionBuilder,
      (StrokeRow, BaseReferences<_$NoteDatabase, $StrokesTable, StrokeRow>),
      StrokeRow,
      PrefetchHooks Function()
    >;
typedef $$PenPresetsTableCreateCompanionBuilder = PenPresetsCompanion Function({
  required String id,
  required String ownerId,
  required String name,
  required String styleJson,
  Value<String?> groupName,
  required bool pinned,
  required String sortKey,
  required int createdAt,
  required int updatedAt,
  Value<int?> deletedAt,
  required String version,
  Value<String?> fieldVersions,
  Value<int> rowid,
});
typedef $$PenPresetsTableUpdateCompanionBuilder = PenPresetsCompanion Function({
  Value<String> id,
  Value<String> ownerId,
  Value<String> name,
  Value<String> styleJson,
  Value<String?> groupName,
  Value<bool> pinned,
  Value<String> sortKey,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int?> deletedAt,
  Value<String> version,
  Value<String?> fieldVersions,
  Value<int> rowid,
});

class $$PenPresetsTableFilterComposer
    extends Composer<_$NoteDatabase, $PenPresetsTable> {
  $$PenPresetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get styleJson => $composableBuilder(
    column: $table.styleJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PenPresetsTableOrderingComposer
    extends Composer<_$NoteDatabase, $PenPresetsTable> {
  $$PenPresetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get styleJson => $composableBuilder(
    column: $table.styleJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PenPresetsTableAnnotationComposer
    extends Composer<_$NoteDatabase, $PenPresetsTable> {
  $$PenPresetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get styleJson =>
      $composableBuilder(column: $table.styleJson, builder: (column) => column);

  GeneratedColumn<String> get groupName =>
      $composableBuilder(column: $table.groupName, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<String> get sortKey =>
      $composableBuilder(column: $table.sortKey, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => column,
  );
}

class $$PenPresetsTableTableManager
    extends
        RootTableManager<
          _$NoteDatabase,
          $PenPresetsTable,
          PenPresetRow,
          $$PenPresetsTableFilterComposer,
          $$PenPresetsTableOrderingComposer,
          $$PenPresetsTableAnnotationComposer,
          $$PenPresetsTableCreateCompanionBuilder,
          $$PenPresetsTableUpdateCompanionBuilder,
          (
            PenPresetRow,
            BaseReferences<_$NoteDatabase, $PenPresetsTable, PenPresetRow>,
          ),
          PenPresetRow,
          PrefetchHooks Function()
        > {
  $$PenPresetsTableTableManager(_$NoteDatabase db, $PenPresetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PenPresetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PenPresetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PenPresetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> styleJson = const Value.absent(),
                Value<String?> groupName = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<String> sortKey = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String?> fieldVersions = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PenPresetsCompanion(
                id: id,
                ownerId: ownerId,
                name: name,
                styleJson: styleJson,
                groupName: groupName,
                pinned: pinned,
                sortKey: sortKey,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                fieldVersions: fieldVersions,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String name,
                required String styleJson,
                Value<String?> groupName = const Value.absent(),
                required bool pinned,
                required String sortKey,
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String version,
                Value<String?> fieldVersions = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PenPresetsCompanion.insert(
                id: id,
                ownerId: ownerId,
                name: name,
                styleJson: styleJson,
                groupName: groupName,
                pinned: pinned,
                sortKey: sortKey,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                fieldVersions: fieldVersions,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PenPresetsTable, PenPresetRow>(table),
                  BaseReferences<
                    _$NoteDatabase,
                    $PenPresetsTable,
                    PenPresetRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PenPresetsTableProcessedTableManager =
    ProcessedTableManager<
      _$NoteDatabase,
      $PenPresetsTable,
      PenPresetRow,
      $$PenPresetsTableFilterComposer,
      $$PenPresetsTableOrderingComposer,
      $$PenPresetsTableAnnotationComposer,
      $$PenPresetsTableCreateCompanionBuilder,
      $$PenPresetsTableUpdateCompanionBuilder,
      (
        PenPresetRow,
        BaseReferences<_$NoteDatabase, $PenPresetsTable, PenPresetRow>,
      ),
      PenPresetRow,
      PrefetchHooks Function()
    >;
typedef $$AssetsTableCreateCompanionBuilder = AssetsCompanion Function({
  required String id,
  required String ownerId,
  required String type,
  required String mimeType,
  required int size,
  Value<String?> fileName,
  required int chunkCount,
  required bool hasLocalBytes,
  Value<String?> storagePath,
  required int createdAt,
  Value<int?> deletedAt,
  required String version,
  Value<String?> fieldVersions,
  Value<int> rowid,
});
typedef $$AssetsTableUpdateCompanionBuilder = AssetsCompanion Function({
  Value<String> id,
  Value<String> ownerId,
  Value<String> type,
  Value<String> mimeType,
  Value<int> size,
  Value<String?> fileName,
  Value<int> chunkCount,
  Value<bool> hasLocalBytes,
  Value<String?> storagePath,
  Value<int> createdAt,
  Value<int?> deletedAt,
  Value<String> version,
  Value<String?> fieldVersions,
  Value<int> rowid,
});

class $$AssetsTableFilterComposer
    extends Composer<_$NoteDatabase, $AssetsTable> {
  $$AssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chunkCount => $composableBuilder(
    column: $table.chunkCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasLocalBytes => $composableBuilder(
    column: $table.hasLocalBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AssetsTableOrderingComposer
    extends Composer<_$NoteDatabase, $AssetsTable> {
  $$AssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chunkCount => $composableBuilder(
    column: $table.chunkCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasLocalBytes => $composableBuilder(
    column: $table.hasLocalBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AssetsTableAnnotationComposer
    extends Composer<_$NoteDatabase, $AssetsTable> {
  $$AssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<int> get chunkCount => $composableBuilder(
    column: $table.chunkCount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasLocalBytes => $composableBuilder(
    column: $table.hasLocalBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => column,
  );
}

class $$AssetsTableTableManager
    extends
        RootTableManager<
          _$NoteDatabase,
          $AssetsTable,
          AssetRow,
          $$AssetsTableFilterComposer,
          $$AssetsTableOrderingComposer,
          $$AssetsTableAnnotationComposer,
          $$AssetsTableCreateCompanionBuilder,
          $$AssetsTableUpdateCompanionBuilder,
          (AssetRow, BaseReferences<_$NoteDatabase, $AssetsTable, AssetRow>),
          AssetRow,
          PrefetchHooks Function()
        > {
  $$AssetsTableTableManager(_$NoteDatabase db, $AssetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<String?> fileName = const Value.absent(),
                Value<int> chunkCount = const Value.absent(),
                Value<bool> hasLocalBytes = const Value.absent(),
                Value<String?> storagePath = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String?> fieldVersions = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssetsCompanion(
                id: id,
                ownerId: ownerId,
                type: type,
                mimeType: mimeType,
                size: size,
                fileName: fileName,
                chunkCount: chunkCount,
                hasLocalBytes: hasLocalBytes,
                storagePath: storagePath,
                createdAt: createdAt,
                deletedAt: deletedAt,
                version: version,
                fieldVersions: fieldVersions,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerId,
                required String type,
                required String mimeType,
                required int size,
                Value<String?> fileName = const Value.absent(),
                required int chunkCount,
                required bool hasLocalBytes,
                Value<String?> storagePath = const Value.absent(),
                required int createdAt,
                Value<int?> deletedAt = const Value.absent(),
                required String version,
                Value<String?> fieldVersions = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssetsCompanion.insert(
                id: id,
                ownerId: ownerId,
                type: type,
                mimeType: mimeType,
                size: size,
                fileName: fileName,
                chunkCount: chunkCount,
                hasLocalBytes: hasLocalBytes,
                storagePath: storagePath,
                createdAt: createdAt,
                deletedAt: deletedAt,
                version: version,
                fieldVersions: fieldVersions,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AssetsTable, AssetRow>(table),
                  BaseReferences<_$NoteDatabase, $AssetsTable, AssetRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$NoteDatabase,
      $AssetsTable,
      AssetRow,
      $$AssetsTableFilterComposer,
      $$AssetsTableOrderingComposer,
      $$AssetsTableAnnotationComposer,
      $$AssetsTableCreateCompanionBuilder,
      $$AssetsTableUpdateCompanionBuilder,
      (AssetRow, BaseReferences<_$NoteDatabase, $AssetsTable, AssetRow>),
      AssetRow,
      PrefetchHooks Function()
    >;
typedef $$RecordingsTableCreateCompanionBuilder = RecordingsCompanion Function({
  required String id,
  required String noteId,
  required String assetId,
  required int durationMs,
  required int startedAt,
  required int createdAt,
  required int updatedAt,
  Value<int?> deletedAt,
  required String version,
  Value<String?> fieldVersions,
  Value<int> rowid,
});
typedef $$RecordingsTableUpdateCompanionBuilder = RecordingsCompanion Function({
  Value<String> id,
  Value<String> noteId,
  Value<String> assetId,
  Value<int> durationMs,
  Value<int> startedAt,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int?> deletedAt,
  Value<String> version,
  Value<String?> fieldVersions,
  Value<int> rowid,
});

class $$RecordingsTableFilterComposer
    extends Composer<_$NoteDatabase, $RecordingsTable> {
  $$RecordingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecordingsTableOrderingComposer
    extends Composer<_$NoteDatabase, $RecordingsTable> {
  $$RecordingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecordingsTableAnnotationComposer
    extends Composer<_$NoteDatabase, $RecordingsTable> {
  $$RecordingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get assetId =>
      $composableBuilder(column: $table.assetId, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => column,
  );
}

class $$RecordingsTableTableManager
    extends
        RootTableManager<
          _$NoteDatabase,
          $RecordingsTable,
          RecordingRow,
          $$RecordingsTableFilterComposer,
          $$RecordingsTableOrderingComposer,
          $$RecordingsTableAnnotationComposer,
          $$RecordingsTableCreateCompanionBuilder,
          $$RecordingsTableUpdateCompanionBuilder,
          (
            RecordingRow,
            BaseReferences<_$NoteDatabase, $RecordingsTable, RecordingRow>,
          ),
          RecordingRow,
          PrefetchHooks Function()
        > {
  $$RecordingsTableTableManager(_$NoteDatabase db, $RecordingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecordingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecordingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecordingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<String> assetId = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int> startedAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String?> fieldVersions = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecordingsCompanion(
                id: id,
                noteId: noteId,
                assetId: assetId,
                durationMs: durationMs,
                startedAt: startedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                fieldVersions: fieldVersions,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String noteId,
                required String assetId,
                required int durationMs,
                required int startedAt,
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String version,
                Value<String?> fieldVersions = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecordingsCompanion.insert(
                id: id,
                noteId: noteId,
                assetId: assetId,
                durationMs: durationMs,
                startedAt: startedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                fieldVersions: fieldVersions,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RecordingsTable, RecordingRow>(table),
                  BaseReferences<
                    _$NoteDatabase,
                    $RecordingsTable,
                    RecordingRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecordingsTableProcessedTableManager =
    ProcessedTableManager<
      _$NoteDatabase,
      $RecordingsTable,
      RecordingRow,
      $$RecordingsTableFilterComposer,
      $$RecordingsTableOrderingComposer,
      $$RecordingsTableAnnotationComposer,
      $$RecordingsTableCreateCompanionBuilder,
      $$RecordingsTableUpdateCompanionBuilder,
      (
        RecordingRow,
        BaseReferences<_$NoteDatabase, $RecordingsTable, RecordingRow>,
      ),
      RecordingRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String valueJson,
  required int updatedAt,
  Value<int?> deletedAt,
  required String version,
  Value<String?> fieldVersions,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> valueJson,
  Value<int> updatedAt,
  Value<int?> deletedAt,
  Value<String> version,
  Value<String?> fieldVersions,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$NoteDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$NoteDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$NoteDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get valueJson =>
      $composableBuilder(column: $table.valueJson, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get fieldVersions => $composableBuilder(
    column: $table.fieldVersions,
    builder: (column) => column,
  );
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$NoteDatabase,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$NoteDatabase, $SettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$NoteDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> valueJson = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String?> fieldVersions = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(
                key: key,
                valueJson: valueJson,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                fieldVersions: fieldVersions,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String valueJson,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String version,
                Value<String?> fieldVersions = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                valueJson: valueJson,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                version: version,
                fieldVersions: fieldVersions,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, SettingRow>(table),
                  BaseReferences<_$NoteDatabase, $SettingsTable, SettingRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$NoteDatabase,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$NoteDatabase, $SettingsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;
typedef $$OutboxTableCreateCompanionBuilder = OutboxCompanion Function({
  Value<int> seq,
  required int rev,
  required String entityKind,
  required String entityId,
  Value<String?> noteId,
  Value<String?> pageId,
  required String op,
  required String changedFields,
  required String hlc,
  required int enqueuedAt,
});
typedef $$OutboxTableUpdateCompanionBuilder = OutboxCompanion Function({
  Value<int> seq,
  Value<int> rev,
  Value<String> entityKind,
  Value<String> entityId,
  Value<String?> noteId,
  Value<String?> pageId,
  Value<String> op,
  Value<String> changedFields,
  Value<String> hlc,
  Value<int> enqueuedAt,
});

class $$OutboxTableFilterComposer
    extends Composer<_$NoteDatabase, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityKind => $composableBuilder(
    column: $table.entityKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get changedFields => $composableBuilder(
    column: $table.changedFields,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get enqueuedAt => $composableBuilder(
    column: $table.enqueuedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxTableOrderingComposer
    extends Composer<_$NoteDatabase, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityKind => $composableBuilder(
    column: $table.entityKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pageId => $composableBuilder(
    column: $table.pageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get changedFields => $composableBuilder(
    column: $table.changedFields,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get enqueuedAt => $composableBuilder(
    column: $table.enqueuedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$NoteDatabase, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<int> get rev =>
      $composableBuilder(column: $table.rev, builder: (column) => column);

  GeneratedColumn<String> get entityKind => $composableBuilder(
    column: $table.entityKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get pageId =>
      $composableBuilder(column: $table.pageId, builder: (column) => column);

  GeneratedColumn<String> get op =>
      $composableBuilder(column: $table.op, builder: (column) => column);

  GeneratedColumn<String> get changedFields => $composableBuilder(
    column: $table.changedFields,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get enqueuedAt => $composableBuilder(
    column: $table.enqueuedAt,
    builder: (column) => column,
  );
}

class $$OutboxTableTableManager
    extends
        RootTableManager<
          _$NoteDatabase,
          $OutboxTable,
          OutboxRow,
          $$OutboxTableFilterComposer,
          $$OutboxTableOrderingComposer,
          $$OutboxTableAnnotationComposer,
          $$OutboxTableCreateCompanionBuilder,
          $$OutboxTableUpdateCompanionBuilder,
          (OutboxRow, BaseReferences<_$NoteDatabase, $OutboxTable, OutboxRow>),
          OutboxRow,
          PrefetchHooks Function()
        > {
  $$OutboxTableTableManager(_$NoteDatabase db, $OutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> seq = const Value.absent(),
                Value<int> rev = const Value.absent(),
                Value<String> entityKind = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String?> noteId = const Value.absent(),
                Value<String?> pageId = const Value.absent(),
                Value<String> op = const Value.absent(),
                Value<String> changedFields = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> enqueuedAt = const Value.absent(),
              }) => OutboxCompanion(
                seq: seq,
                rev: rev,
                entityKind: entityKind,
                entityId: entityId,
                noteId: noteId,
                pageId: pageId,
                op: op,
                changedFields: changedFields,
                hlc: hlc,
                enqueuedAt: enqueuedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> seq = const Value.absent(),
                required int rev,
                required String entityKind,
                required String entityId,
                Value<String?> noteId = const Value.absent(),
                Value<String?> pageId = const Value.absent(),
                required String op,
                required String changedFields,
                required String hlc,
                required int enqueuedAt,
              }) => OutboxCompanion.insert(
                seq: seq,
                rev: rev,
                entityKind: entityKind,
                entityId: entityId,
                noteId: noteId,
                pageId: pageId,
                op: op,
                changedFields: changedFields,
                hlc: hlc,
                enqueuedAt: enqueuedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxTable, OutboxRow>(table),
                  BaseReferences<_$NoteDatabase, $OutboxTable, OutboxRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$NoteDatabase,
      $OutboxTable,
      OutboxRow,
      $$OutboxTableFilterComposer,
      $$OutboxTableOrderingComposer,
      $$OutboxTableAnnotationComposer,
      $$OutboxTableCreateCompanionBuilder,
      $$OutboxTableUpdateCompanionBuilder,
      (OutboxRow, BaseReferences<_$NoteDatabase, $OutboxTable, OutboxRow>),
      OutboxRow,
      PrefetchHooks Function()
    >;

class $NoteDatabaseManager {
  final _$NoteDatabase _db;
  $NoteDatabaseManager(this._db);
  $$KvTableTableManager get kv => $$KvTableTableManager(_db, _db.kv);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db, _db.folders);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db, _db.notes);
  $$PagesTableTableManager get pages =>
      $$PagesTableTableManager(_db, _db.pages);
  $$StrokesTableTableManager get strokes =>
      $$StrokesTableTableManager(_db, _db.strokes);
  $$PenPresetsTableTableManager get penPresets =>
      $$PenPresetsTableTableManager(_db, _db.penPresets);
  $$AssetsTableTableManager get assets =>
      $$AssetsTableTableManager(_db, _db.assets);
  $$RecordingsTableTableManager get recordings =>
      $$RecordingsTableTableManager(_db, _db.recordings);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
}
