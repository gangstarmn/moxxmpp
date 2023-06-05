import 'dart:async';

import 'package:moxxmpp/moxxmpp.dart';

/// Representation of a <occupant-id /> element.
class OccupantIdData {
  const OccupantIdData(
    this.id,
  );

  /// The unique occupant id.
  final String id;

  XMLNode toXML() {
    return XMLNode.xmlns(
      tag: 'occupant-id',
      xmlns: stableIdXmlns,
      attributes: {
        'id': id,
      },
    );
  }
}

class OccupantIdManager extends XmppManagerBase {
  OccupantIdManager() : super(occupantIdManager);

  @override
  List<String> getDiscoFeatures() => [stableIdXmlns];

  @override
  List<StanzaHandler> getIncomingStanzaHandlers() => [
        StanzaHandler(
          tagName: 'occupant-id',
          tagXmlns: occupantIdXmlns,
          callback: _onOccupantId,
        )
      ];

  @override
  Future<void> onXmppEvent(XmppEvent event) async {
    if (event is PresenceReceivedEvent) {
      unawaited(_onPresence(event));
    }
  }

  @override
  Future<bool> isSupported() async => true;

  Future<StanzaHandlerData> _onOccupantId(
    Stanza occupantId,
    StanzaHandlerData state,
  ) async =>
      state.copyWith(
        occupantId: OccupantIdData(occupantId.attributes['id']! as String),
      );

  Future<void> _onPresence(PresenceReceivedEvent event) async {
    final occupantIdElement =
        event.presence.firstTag('occupant-id', xmlns: occupantIdXmlns);
    if (occupantIdElement == null) {
      return;
    }
    final occupantId = OccupantIdData(
      occupantIdElement.attributes['id']! as String,
    );
    getAttributes().sendEvent(
      MUCMemberReceivedEvent(
        event.jid.toBare(),
        event.jid.resource,
        occupantId,
      ),
    );
  }
}
