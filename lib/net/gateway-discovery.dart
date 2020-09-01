import 'package:dvote/models/dart/gateway.pb.dart';
import 'package:dvote/net/bootnodes.dart';
import 'package:dvote/net/gateway-dvote.dart';
import 'package:dvote/net/gateway-web3.dart';
import 'package:dvote/net/gateway.dart';
import 'package:dvote/util/dev.dart';

/// Retrieve a list of working gateways. If no bootnode URI is provided, the well-known URI is used.
Future<List<Gateway>> discoverGateways(
    {String bootnodeUri,
    String networkId = "xdai",
    int maxGatewayCount = 5}) async {
  if (bootnodeUri is! String || bootnodeUri.length < 1) {
    bootnodeUri = await resolveWellKnownBootnodeUri(networkId);
  }

  final info = await fetchBootnodeInfo(bootnodeUri);

  return discoverGatewaysFromBootnodeInfo(info,
      networkId: networkId, maxGatewayCount: maxGatewayCount);
}

// Digests the bootnode info into a list of working gateways, featuring web3 and DVote nodes
Future<List<Gateway>> discoverGatewaysFromBootnodeInfo(BootNodeGateways info,
    {String networkId = "xdai", int maxGatewayCount = 5}) async {
  BootNodeGateways_NetworkNodes networkNodes;

  switch (networkId) {
    case "mainnet":
      networkNodes = info.homestead;
      break;
    case "goerli":
      networkNodes = info.goerli;
      break;
    case "xdai":
      networkNodes = info.xdai;
      break;
    default:
      throw Exception("Invalid network ID: " + networkId);
  }

  final web3Candidates = networkNodes.web3;
  final dvoteCandidates = networkNodes.dvote;
  web3Candidates.shuffle();
  dvoteCandidates.shuffle();

  // Filter working web3 nodes
  var web3Nodes = <Web3Gateway>[];

  await Future.wait(web3Candidates.map((candidate) {
    return Web3Gateway.isSyncing(candidate.uri).then((syncing) {
      if (!syncing)
        web3Nodes.add(Web3Gateway(candidate.uri));
      else
        devPrint("[Discovery] Web3 node ${candidate.uri} is syncing: Skip");
    }).catchError((err) {
      devPrint("[Discovery] ${candidate.uri} failed: $err");
    });
  }));

  // TODO: Filter also by supported API's

  // Filter working DVote nodes
  var dvoteNodes = <DVoteGateway>[];

  await Future.wait(dvoteCandidates.map((candidate) {
    final gw = DVoteGateway(candidate.uri, publicKey: candidate.pubKey);

    // updateStatus will throw if it is down
    return gw.updateStatus().then((_) {
      // gw.health and gw.supportedApis will be populated otherwise
      dvoteNodes.add(gw); // working
    }).catchError((err) {
      devPrint("[Discovery] ${candidate.uri} failed: $err");
    });
  }));

  if (web3Nodes.length == 0 || dvoteNodes.length == 0) return <Gateway>[];

  // Map DVote+Web3 objects into a single list
  return arrangeHealthierNodes(web3Nodes, dvoteNodes, maxGatewayCount);
}

Future<List<Gateway>> arrangeHealthierNodes(List<Web3Gateway> web3Nodes,
    List<DVoteGateway> dvoteNodes, int maxGatewayCount) async {
  assert(web3Nodes.length >= 1);
  assert(dvoteNodes.length >= 1);
  assert(maxGatewayCount >= 1);

  dvoteNodes.sort((a, b) {
    if (a.health is! int && b.health is! int)
      return 0;
    else if (a.health is! int)
      return 1;
    else if (b.health is! int) return -1;
    return b.health - a.health;
  });

  if (dvoteNodes.length > maxGatewayCount) {
    dvoteNodes = dvoteNodes.sublist(0, maxGatewayCount);
  }
  if (web3Nodes.length > maxGatewayCount) {
    web3Nodes = web3Nodes.sublist(0, maxGatewayCount);
  }

  List<Gateway> result = <Gateway>[];
  if (dvoteNodes.length >= web3Nodes.length) {
    // populate using DVote nodes as the base
    for (int i = 0; i < dvoteNodes.length; i++) {
      result.add(Gateway(dvoteNodes[i], web3Nodes[i % web3Nodes.length]));
    }
  } else {
    // populate using Web3 nodes as the base
    for (int i = 0; i < web3Nodes.length; i++) {
      result.add(Gateway(dvoteNodes[i % dvoteNodes.length], web3Nodes[i]));
    }
  }
  return result;
}
