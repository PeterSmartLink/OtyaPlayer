import 'dart:async';

import 'package:flutter/material.dart';

import '../../transfer/data/transfer_hotspot_service.dart';
import '../../transfer/presentation/transfer_screen.dart';

/// Compatibility entry for older code and deep links.
///
/// User-facing behavior remains owned by [TransferScreen]. This entry only
/// prepares modern Android local-network permission when the user explicitly
/// opens Transfer; it does not create a second transport or request anything at
/// app startup.
class AirDropScreen extends StatefulWidget {
  const AirDropScreen({super.key});

  @override
  State<AirDropScreen> createState() => _AirDropScreenState();
}

class _AirDropScreenState extends State<AirDropScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(TransferHotspotService.instance.ensureLocalNetworkAccess());
  }

  @override
  Widget build(BuildContext context) => const TransferScreen();
}
