import 'dart:io';

class NetworkAddressCandidate {
  const NetworkAddressCandidate({
    required this.ip,
    required this.interfaceName,
  });

  final String ip;
  final String interfaceName;
}

class IpAddressUtils {
  static const List<String> _virtualInterfaceMarkers = [
    'tailscale',
    'wg',
    'wireguard',
    'tun',
    'tap',
    'docker',
    'veth',
    'vmware',
    'virtualbox',
    'vbox',
    'hyper-v',
    'wsl',
    'loopback',
  ];

  static const List<String> _preferredInterfaceMarkers = [
    'wi-fi',
    'wifi',
    'wlan',
    'ethernet',
    'lan',
    'eth',
    'en',
  ];

  static bool isUsableIpv4(String? ip) {
    if (ip == null || ip.isEmpty) return false;
    final parsed = InternetAddress.tryParse(ip);
    if (parsed == null || parsed.type != InternetAddressType.IPv4) return false;
    if (parsed.isLoopback || parsed.isLinkLocal || parsed.isMulticast) {
      return false;
    }
    if (ip == '0.0.0.0' || ip == '255.255.255.255') return false;
    return true;
  }

  static bool isRfc1918PrivateIpv4(String ip) {
    final parsed = InternetAddress.tryParse(ip);
    if (parsed == null || parsed.type != InternetAddressType.IPv4) return false;
    final octets = ip.split('.');
    if (octets.length != 4) return false;
    final a = int.tryParse(octets[0]);
    final b = int.tryParse(octets[1]);
    if (a == null || b == null) return false;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  static int scoreIpv4Candidate(NetworkAddressCandidate candidate) {
    if (!isUsableIpv4(candidate.ip)) return -10000;

    var score = 100;
    if (isRfc1918PrivateIpv4(candidate.ip)) {
      score += 250;
    } else if (_isCarrierGradeNat(candidate.ip)) {
      score += 80;
    }

    final iface = candidate.interfaceName.toLowerCase();
    if (_virtualInterfaceMarkers.any(iface.contains)) {
      score -= 200;
    }
    if (_preferredInterfaceMarkers.any(iface.contains)) {
      score += 40;
    }

    return score;
  }

  static Future<String?> findBestLocalIpv4() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );

    NetworkAddressCandidate? best;
    var bestScore = -10000;

    for (final networkInterface in interfaces) {
      for (final address in networkInterface.addresses) {
        final candidate = NetworkAddressCandidate(
          ip: address.address,
          interfaceName: networkInterface.name,
        );
        final score = scoreIpv4Candidate(candidate);
        if (score > bestScore) {
          best = candidate;
          bestScore = score;
        }
      }
    }

    return best?.ip;
  }

  static bool _isCarrierGradeNat(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    return a == 100 && b >= 64 && b <= 127;
  }
}
