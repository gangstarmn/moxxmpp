import 'package:moxxmpp/src/connection.dart';
import 'package:moxxmpp/src/events.dart';
import 'package:moxxmpp/src/jid.dart';
import 'package:moxxmpp/src/managers/base.dart';
import 'package:moxxmpp/src/managers/data.dart';
import 'package:moxxmpp/src/managers/handlers.dart';
import 'package:moxxmpp/src/managers/namespaces.dart';
import 'package:moxxmpp/src/namespaces.dart';
import 'package:moxxmpp/src/stanza.dart';
import 'package:moxxmpp/src/stringxml.dart';

/// A function that will be called when presence, outside of subscription request
/// management, will be sent. Useful for managers that want to add [XMLNode]s to said
/// presence.
typedef PresencePreSendCallback = Future<List<XMLNode>> Function();

/// A mandatory manager that handles initial presence sending, sending of subscription
/// request management requests and triggers events for incoming presence stanzas.
class PresenceManager extends XmppManagerBase {
  PresenceManager() : super(presenceManager);

  /// The list of pre-send callbacks.
  final List<PresencePreSendCallback> _presenceCallbacks = List.empty(growable: true);

  @override
  List<StanzaHandler> getIncomingStanzaHandlers() => [
    StanzaHandler(
      stanzaTag: 'presence',
      callback: _onPresence,
    )
  ];

  @override
  List<String> getDiscoFeatures() => [ capsXmlns ];

  @override
  Future<bool> isSupported() async => true;

  /// Register the pre-send callback [callback].
  void registerPreSendCallback(PresencePreSendCallback callback) {
    _presenceCallbacks.add(callback);
  }
  
  Future<StanzaHandlerData> _onPresence(Stanza presence, StanzaHandlerData state) async {
    final attrs = getAttributes();
    switch (presence.type) {
      case 'subscribe':
      case 'subscribed': {
        attrs.sendEvent(
          SubscriptionRequestReceivedEvent(from: JID.fromString(presence.from!)),
        );
        return state.copyWith(done: true);
      }
      default: break;
    }

    if (presence.from != null) {
      logger.finest("Received presence from '${presence.from}'");

      getAttributes().sendEvent(PresenceReceivedEvent(JID.fromString(presence.from!), presence));
      return state.copyWith(done: true);
    } 

    return state;
  }

  /// Sends the initial presence to enable receiving messages.
  Future<void> sendInitialPresence() async {
    final children = List<XMLNode>.from([
      XMLNode(
        tag: 'show',
        text: 'chat',
      ),
    ]);

    for (final callback in _presenceCallbacks) {
      children.addAll(
        await callback(),
      );
    }

    final attrs = getAttributes();
    attrs.sendNonza(
      Stanza.presence(
        from: attrs.getFullJID().toString(),
        children: children,
      ),
    );
  }

  /// Send an unavailable presence with no 'to' attribute.
  void sendUnavailablePresence() {
    getAttributes().sendStanza(
      Stanza.presence(
        type: 'unavailable',
      ),
      addFrom: StanzaFromType.full,
    );
  }
  
  /// Sends a subscription request to [to].
  void sendSubscriptionRequest(String to) {
    getAttributes().sendStanza(
      Stanza.presence(
        type: 'subscribe',
        to: to,
      ),
      addFrom: StanzaFromType.none,
    );
  }

  /// Sends an unsubscription request to [to].
  void sendUnsubscriptionRequest(String to) {
    getAttributes().sendStanza(
      Stanza.presence(
        type: 'unsubscribe',
        to: to,
      ),
      addFrom: StanzaFromType.none,
    );
  }

  /// Accept a presence subscription request for [to].
  void sendSubscriptionRequestApproval(String to) {
    getAttributes().sendStanza(
      Stanza.presence(
        type: 'subscribed',
        to: to,
      ),
      addFrom: StanzaFromType.none,
    );
  }

  /// Reject a presence subscription request for [to].
  void sendSubscriptionRequestRejection(String to) {
    getAttributes().sendStanza(
      Stanza.presence(
        type: 'unsubscribed',
        to: to,
      ),
      addFrom: StanzaFromType.none,
    );
  }
}
