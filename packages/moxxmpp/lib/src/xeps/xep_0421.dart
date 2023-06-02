import 'dart:async';

import 'package:moxxmpp/moxxmpp.dart';

/// Representation of a <occupant-id /> element.
class OccupantIdData {
  const OccupantIdData(
    this.id,
  );

  /// The unique occupant id.
  final String id;

  XMLNode toXml() {
    return XMLNode.xmlns(
      tag: 'occupant-id',
      xmlns: stableIdXmlns,
      attributes: {
        'id': id,
      },
    );
  }
}

XMLNode makeOccupantIdElement(String id) {
  return XMLNode.xmlns(
    tag: 'origin-id',
    xmlns: stableIdXmlns,
    attributes: {'id': id},
  );
}

class OccupantIdManager extends XmppManagerBase {
  OccupantIdManager() : super(occupantIdManager);

  @override
  List<String> getDiscoFeatures() => [stableIdXmlns];

  @override
  List<StanzaHandler> getIncomingStanzaHandlers() => [
        StanzaHandler(
          stanzaTag: 'message',
          callback: _onMessage,
          // Before the MessageManager
          priority: -99,
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

  Future<StanzaHandlerData> _onMessage(
    Stanza message,
    StanzaHandlerData state,
  ) async {
    OccupantIdData? occupantId;
    final occupantIdElement =
        message.firstTag('occupant-id', xmlns: occupantIdXmlns);

    // Process the occupant id
    if (occupantIdElement != null) {
      occupantId =
          OccupantIdData(occupantIdElement.attributes['id']! as String);
    }

    // Process the stanza id tag

    return state.copyWith(
      occupantId: occupantId,
    );
  }

  Future<void> _onPresence(PresenceReceivedEvent event) async {
    OccupantIdData? occupantId;
    final occupantIdElement =
        event.presence.firstTag('occupant-id', xmlns: occupantIdXmlns);
    if (occupantIdElement == null) {
      return;
    } else {
      occupantId = OccupantIdData(
        occupantIdElement.attributes['id']! as String,
      );
    }
    getAttributes().sendEvent(
      MUCMemberReceivedEvent(
        event.jid.toBare(),
        event.jid.resource,
        occupantId,
      ),
    );
  }
}
