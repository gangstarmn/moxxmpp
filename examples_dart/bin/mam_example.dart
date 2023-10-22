import 'package:example_dart/arguments.dart';
import 'package:example_dart/socket.dart';
import 'package:logging/logging.dart';
import 'package:moxxmpp/moxxmpp.dart';

void main(List<String> args) async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}|${record.time}: ${record.message}');
  });

  final parser = ArgumentParser()
    ..parser.addOption('mam-jid', help: 'The JID to query the archive from');
  final options = parser.handleArguments(args);
  if (options == null) {
    return;
  }

  final connection = XmppConnection(
    TestingReconnectionPolicy(),
    AlwaysConnectedConnectivityManager(),
    ClientToServerNegotiator(),
    ExampleTCPSocketWrapper(parser.srvRecord, false),
  )..connectionSettings = parser.connectionSettings;

  await connection.registerManagers([
    MessageManager(),
    MessageArchiveManagementManager(),
  ]);

  await connection.registerFeatureNegotiators([
    SaslPlainNegotiator(),
    ResourceBindingNegotiator(),
    StartTlsNegotiator(),
  ]);

  connection.asBroadcastStream().listen((event) {
    if (event is! MessageEvent) {
      return;
    }

    if (event.get<MAMData>() == null) {
      return;
    }

    final body = event.extensions.get<MessageBodyData>()?.body;
    print('[<-- ${event.from} MAM] $body');
  });

  final result = await connection.connect(
    shouldReconnect: true,
    waitUntilLogin: true,
  );
  if (!result.isType<bool>()) {
    print('Failed to connect to server');
    return;
  }

  final mam =
      connection.getManagerById<MessageArchiveManagementManager>(mamManager)!;
  final queryResult = await mam.requestMessages(
    JID.fromString(options['mam-jid']),
    pageSize: 10,
  );
  if (queryResult.isType<MAMError>()) {
    Logger.root.severe('MAM query failed');
  } else {
    final numMessages = queryResult.get<int>();
    Logger.root.info('MAM query returned $numMessages message stanzas');
  }
  Logger.root.info('MAM query done. Disconnecting...');

  await connection.disconnect();
}
