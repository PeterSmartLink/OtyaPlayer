import 'package:flutter/material.dart';

import '../../transfer/presentation/transfer_screen.dart';

/// Compatibility entry for older routes/deep links.
///
/// Send/Receive owns its connection setup directly. Keeping this wrapper tiny
/// prevents the feature from feeling like a second transfer app layered on top
/// of Otya and avoids exposing an extra "offline network" control.
class AirDropScreen extends StatelessWidget {
  const AirDropScreen({super.key});

  @override
  Widget build(BuildContext context) => const TransferScreen();
}
