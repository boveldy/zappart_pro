import 'package:cloud_functions/cloud_functions.dart';

/// Région des Cloud Functions Zappart (même projet que l'app officielle).
const kCloudRegion = 'europe-west3';

HttpsCallable cloudFunction(String name) =>
    FirebaseFunctions.instanceFor(region: kCloudRegion).httpsCallable(name);
