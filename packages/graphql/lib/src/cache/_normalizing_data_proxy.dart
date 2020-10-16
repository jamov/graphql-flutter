import 'package:graphql/src/cache/fragment.dart';
import "package:meta/meta.dart";

import 'package:gql_exec/gql_exec.dart' show Request;
import 'package:normalize/normalize.dart';

import './data_proxy.dart';
import '../utilities/helpers.dart';

typedef DataIdResolver = String Function(Map<String, Object> object);

/// Implements the core (de)normalization api leveraged by the cache and proxy,
///
/// [readNormalized] and [writeNormalized] must still be supplied by the implementing class
abstract class NormalizingDataProxy extends GraphQLDataProxy {
  /// `typePolicies` to pass down to `normalize`
  Map<String, TypePolicy> get typePolicies;

  /// Optional `dataIdFromObject` function to pass through to [normalize]
  DataIdResolver get dataIdFromObject;

  /// Whether to add `__typename` automatically.
  ///
  /// This is `false` by default because [gql] automatically adds `__typename` already.
  ///
  /// If [addTypename] is true, it is important for the client
  /// to add `__typename` to each request automatically as well.
  /// Otherwise, a round trip to the cache will nullify results unless
  /// [returnPartialData] is `true`
  bool addTypename = false;

  /// Used for testing
  @protected
  bool get returnPartialData => false;

  /// Flag used to request a (re)broadcast from the [QueryManager].
  ///
  /// This is set on every [writeQuery] and [writeFragment] by default.
  @protected
  @visibleForTesting
  bool broadcastRequested = false;

  /// Read normaized data from the cache
  ///
  /// Called from [readQuery] and [readFragment], which handle denormalization.
  ///
  /// The key differentiating factor for an implementing `cache` or `proxy`
  /// is usually how they handle [optimistic] reads.
  @protected
  dynamic readNormalized(String rootId, {bool optimistic});

  /// Write normalized data into the cache.
  ///
  /// Called from [writeQuery] and [writeFragment].
  /// Implementors are expected to handle deep merging results themselves
  @protected
  void writeNormalized(String dataId, dynamic value);

  /// Variable sanitizer for referencing custom scalar types in cache keys.
  @protected
  SanitizeVariables sanitizeVariables;

  Map<String, dynamic> readQuery(
    Request request, {
    bool optimistic = true,
  }) =>
      denormalizeOperation(
        // provided from cache
        read: (dataId) => readNormalized(dataId, optimistic: optimistic),
        typePolicies: typePolicies,
        returnPartialData: returnPartialData,
        addTypename: addTypename ?? false,
        // provided from request
        document: request.operation.document,
        operationName: request.operation.operationName,
        variables: sanitizeVariables(request.variables),
      );

  Map<String, dynamic> readFragment(
    FragmentRequest fragmentRequest, {
    bool optimistic = true,
  }) =>
      denormalizeFragment(
        // provided from cache
        read: (dataId) => readNormalized(dataId, optimistic: optimistic),
        typePolicies: typePolicies,
        dataIdFromObject: dataIdFromObject,
        returnPartialData: returnPartialData,
        addTypename: addTypename ?? false,
        // provided from request
        document: fragmentRequest.fragment.document,
        idFields: fragmentRequest.idFields,
        fragmentName: fragmentRequest.fragment.fragmentName,
        variables: sanitizeVariables(fragmentRequest.variables),
      );

  void writeQuery(
    Request request, {
    Map<String, dynamic> data,
    bool broadcast = true,
  }) {
    normalizeOperation(
      // provided from cache
      write: (dataId, value) => writeNormalized(dataId, value),
      read: (dataId) => readNormalized(dataId),
      typePolicies: typePolicies,
      dataIdFromObject: dataIdFromObject,
      // provided from request
      document: request.operation.document,
      operationName: request.operation.operationName,
      variables: sanitizeVariables(request.variables),
      // data
      data: data,
    );
    if (broadcast ?? true) {
      broadcastRequested = true;
    }
  }

  void writeFragment(
    FragmentRequest request, {
    @required Map<String, dynamic> data,
    bool broadcast = true,
  }) {
    normalizeFragment(
      // provided from cache
      write: (dataId, value) => writeNormalized(dataId, value),
      read: (dataId) => readNormalized(dataId),
      typePolicies: typePolicies,
      dataIdFromObject: dataIdFromObject,
      // provided from request
      document: request.fragment.document,
      idFields: request.idFields,
      fragmentName: request.fragment.fragmentName,
      variables: sanitizeVariables(request.variables),
      // data
      data: data,
    );
    if (broadcast ?? true) {
      broadcastRequested = true;
    }
  }
}