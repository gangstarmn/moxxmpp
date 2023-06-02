import 'dart:async';

import 'package:moxxmpp/moxxmpp.dart';

/// Representation of a <occupant-id /> element.
class OccupantIdData implements StanzaHandlerExtension {
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
        ),
        StanzaHandler(
          stanzaTag: 'presence',
          tagName: 'occupant-id',
          tagXmlns: occupantIdXmlns,
          callback: _onPresence,
          priority: PresenceManager.presenceHandlerPriority + 1,
        ),
      ];

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
    state.extensions.set(occupantId!);
    return state;
  }

  Future<StanzaHandlerData> _onPresence(
    Stanza stanza,
    StanzaHandlerData state,
  ) async {
    OccupantIdData? occupantId;
    final occupantIdElement =
        stanza.firstTag('occupant-id', xmlns: occupantIdXmlns);
    if (occupantIdElement == null) {
      return state;
    }
    occupantId = OccupantIdData(
      occupantIdElement.attributes['id']! as String,
    );

    getAttributes().sendEvent(
      MUCMemberReceivedEvent(
        JID.fromString(stanza.from!).toBare(),
        JID.fromString(stanza.from!).resource,
        occupantId,
      ),
    );
    return state;
  }
}
