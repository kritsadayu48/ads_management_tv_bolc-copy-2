import 'package:ads_management_tv/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/ad_bloc.dart';
import '../services/ad_service.dart';
import '../services/device_service.dart';

class AdBlocWrapper extends StatelessWidget {
  final String deviceId;

  const AdBlocWrapper({
    Key? key,
    required this.deviceId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AdBloc>(
      create: (context) => AdBloc(
        deviceId: deviceId,
        adService: AdService(),
        deviceService: DeviceService(),
      ),
      child: AdPlayerScreen(deviceId: deviceId),
    );
  }
}
