import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:moxxmpp/src/events.dart';
import 'package:moxxmpp/src/managers/namespaces.dart';
import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/negotiators/namespaces.dart';
import 'package:moxxmpp/src/negotiators/negotiator.dart';
import 'package:moxxmpp/src/negotiators/sasl2.dart';
import 'package:moxxmpp/src/stringxml.dart';
import 'package:moxxmpp/src/types/result.dart';
import 'package:moxxmpp/src/xeps/xep_0198/nonzas.dart';
import 'package:moxxmpp/src/xeps/xep_0198/state.dart';
import 'package:moxxmpp/src/xeps/xep_0198/xep_0198.dart';
import 'package:moxxmpp/src/xeps/xep_0352.dart';

enum _StreamManagementNegotiatorState {
  // We have not done anything yet
  ready,
  // The SM resume has been requested
  resumeRequested,
  // The SM enablement has been requested
  enableRequested,
}

/// NOTE: The stream management negotiator requires that loadState has been called on the
///       StreamManagementManager at least once before connecting, if stream resumption
///       is wanted.
class StreamManagementNegotiator extends Sasl2FeatureNegotiator {
  StreamManagementNegotiator()
      : super(10, false, smXmlns, streamManagementNegotiator);

  /// Stream Management negotiation state.
  _StreamManagementNegotiatorState _state =
      _StreamManagementNegotiatorState.ready;

  /// Flag indicating whether the resume failed (true) or succeeded (false).
  bool _resumeFailed = false;

  /// Flag indicating whether the current stream is resumed (true) or not (false).
  bool _isResumed = false;

  /// Logger
  final Logger _log = Logger('StreamManagementNegotiator');

  /// True if Stream Management is supported on this stream.
  bool _supported = false;
  bool get isSupported => _supported;

  /// True if the current stream is resumed. False if not.
  bool get isResumed => _isResumed;

  @override
  bool canInlineFeature(List<XMLNode> features) {
    final sm = attributes.getManagerById<StreamManagementManager>(smManager)!;

    // We do not check here for authentication as enabling/resuming happens inline
    // with the authentication.
    if (sm.state.streamResumptionId != null && !_resumeFailed) {
      // We can try to resume the stream or enable the stream
      return features.firstWhereOrNull(
            (child) => child.xmlns == smXmlns,
          ) !=
          null;
    } else {
      // We can try to enable SM
      return features.firstWhereOrNull(
            (child) => child.tag == 'enable' && child.xmlns == smXmlns,
          ) !=
          null;
    }
  }

  @override
  bool matchesFeature(List<XMLNode> features) {
    final sm = attributes.getManagerById<StreamManagementManager>(smManager)!;

    if (sm.state.streamResumptionId != null && !_resumeFailed) {
      // We could do Stream resumption
      return super.matchesFeature(features) && attributes.isAuthenticated();
    } else {
      // We cannot do a stream resumption
      return super.matchesFeature(features) &&
          attributes.getConnection().resource.isNotEmpty &&
          attributes.isAuthenticated();
    }
  }

  Future<void> _onStreamResumptionFailed() async {
    await attributes.sendEvent(StreamResumeFailedEvent());
    final sm = attributes.getManagerById<StreamManagementManager>(smManager)!;

    // We have to do this because we otherwise get a stanza stuck in the queue,
    // thus spamming the server on every <a /> nonza we receive.
    // ignore: cascade_invocations
    await sm.setState(StreamManagementState(0, 0));
    await sm.commitState();

    _resumeFailed = true;
    _isResumed = false;
    _state = _StreamManagementNegotiatorState.ready;
  }

  Future<void> _onStreamResumptionSuccessful(XMLNode resumed) async {
    assert(resumed.tag == 'resumed', 'The correct element must be passed');

    final h = int.parse(resumed.attributes['h']! as String);
    await attributes.sendEvent(StreamResumedEvent(h: h));

    _resumeFailed = false;
    _isResumed = true;
  }

  @override
  Future<Result<NegotiatorState, NegotiatorError>> negotiate(
    XMLNode nonza,
  ) async {
    // negotiate is only called when we matched the stream feature, so we know
    // that the server advertises it.
    _supported = true;

    switch (_state) {
      case _StreamManagementNegotiatorState.ready:
        final sm =
            attributes.getManagerById<StreamManagementManager>(smManager)!;
        final srid = sm.state.streamResumptionId;
        final h = sm.state.s2c;

        // Attempt stream resumption first
        if (srid != null) {
          _log.finest(
            'Found stream resumption Id. Attempting to perform stream resumption',
          );
          _state = _StreamManagementNegotiatorState.resumeRequested;
          attributes.sendNonza(StreamManagementResumeNonza(srid, h));
        } else {
          _log.finest('Attempting to enable stream management');
          _state = _StreamManagementNegotiatorState.enableRequested;
          attributes.sendNonza(StreamManagementEnableNonza());
        }

        return const Result(NegotiatorState.ready);
      case _StreamManagementNegotiatorState.resumeRequested:
        if (nonza.tag == 'resumed') {
          _log.finest('Stream Management resumption successful');

          assert(
            attributes.getFullJID().resource != '',
            'Resume only works when we already have a resource bound and know about it',
          );

          final csi = attributes.getManagerById(csiManager) as CSIManager?;
          if (csi != null) {
            csi.restoreCSIState();
          }

          await _onStreamResumptionSuccessful(nonza);
          return const Result(NegotiatorState.skipRest);
        } else {
          // We assume it is <failed />
          _log.info(
            'Stream resumption failed. Expected <resumed />, got ${nonza.tag}, Proceeding with new stream...',
          );
          await _onStreamResumptionFailed();
          return const Result(NegotiatorState.retryLater);
        }
      case _StreamManagementNegotiatorState.enableRequested:
        if (nonza.tag == 'enabled') {
          _log.finest('Stream Management enabled');

          final id = nonza.attributes['id'] as String?;
          if (id != null &&
              ['true', '1'].contains(nonza.attributes['resume'])) {
            _log.info('Stream Resumption available');
          }

          await attributes.sendEvent(
            StreamManagementEnabledEvent(
              resource: attributes.getFullJID().resource,
              id: id,
              location: nonza.attributes['location'] as String?,
            ),
          );

          return const Result(NegotiatorState.done);
        } else {
          // We assume a <failed />
          _log.warning('Stream Management enablement failed');
          return const Result(NegotiatorState.done);
        }
    }
  }

  @override
  void reset() {
    _state = _StreamManagementNegotiatorState.ready;
    _supported = false;
    _resumeFailed = false;
    _isResumed = false;

    super.reset();
  }

  @override
  Future<List<XMLNode>> onSasl2FeaturesReceived(XMLNode sasl2Features) async {
    final inline = sasl2Features.firstTag('inline')!;
    final resume = inline.firstTag('resume', xmlns: smXmlns);

    if (resume == null) {
      return [];
    }

    final sm = attributes.getManagerById<StreamManagementManager>(smManager)!;
    final srid = sm.state.streamResumptionId;
    final h = sm.state.s2c;
    if (srid == null) {
      _log.finest('No srid');
      return [];
    }

    return [
      XMLNode.xmlns(
        tag: 'resume',
        xmlns: smXmlns,
        attributes: {
          'h': h.toString(),
          'previd': srid,
        },
      ),
    ];
  }

  @override
  Future<Result<bool, NegotiatorError>> onSasl2Success(XMLNode response) async {
    final resumed = response.firstTag('resumed', xmlns: smXmlns);
    if (resumed == null) {
      _log.warning('Inline stream resumption failed');
      await _onStreamResumptionFailed();
      state = NegotiatorState.retryLater;
      return const Result(true);
    }

    _log.finest('Inline stream resumption successful');
    await _onStreamResumptionSuccessful(resumed);
    state = NegotiatorState.skipRest;

    attributes.removeNegotiatingFeature(smXmlns);
    attributes.removeNegotiatingFeature(bindXmlns);

    return const Result(true);
  }

  @override
  Future<void> postRegisterCallback() async {
    attributes
        .getNegotiatorById<Sasl2Negotiator>(sasl2Negotiator)
        ?.registerNegotiator(this);
  }
}
