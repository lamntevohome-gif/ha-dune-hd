import 'package:evoknx_ui/evoknx_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:knx_config/knx_config.dart' show cameraUrl;
import 'package:media_kit/media_kit.dart';

import 'app_store.dart';
import 'camera_live.dart';
import 'home_screen.dart';
import 'intro_screen.dart';
import 'share_intake.dart';
import 'splash_gate.dart';
import 'welcome_screen.dart';

/// Lets the share handler show dialogs over whatever screen is open.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Camera cards play real video in the App (the Editor only shows the address).
  EvoHooks.camera = (context, cam) => LiveCamera(key: ValueKey(cameraUrl(cam)), cam: cam);
  await Mdi.load();
  final store = AppStore();
  await store.load();
  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  runApp(EvoknxApp(store: store));
  ShareIntake(store, navigatorKey).start();
}

class EvoknxApp extends StatelessWidget {
  const EvoknxApp({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final pal = AppPalette.of(store.config == null ? 'light' : store.mode);
        // Light text on the screen = a dark theme (Xám has a mid-grey screen with dark text).
        final dark = pal.sInk.computeLuminance() > 0.5;
        SystemChrome.setSystemUIOverlayStyle(dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark);
        return LangScope(
          lang: appLang,
          child: MaterialApp(
            key: ValueKey(appLang.code),
            navigatorKey: navigatorKey,
            title: 'EvoKNX',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              brightness: dark ? Brightness.dark : Brightness.light,
              fontFamily: kEvoFont,
              colorSchemeSeed: pal.accent,
              scaffoldBackgroundColor: pal.screen,
            ),
            // Text follows the App's own size setting, not the phone's, so the
            // cards look as designed in the Editor.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(store.textScale)),
              child: child!,
            ),
            home: !store.introSeen
                ? IntroScreen(store: store, onDone: store.markIntroSeen)
                : store.config == null
                ? WelcomeScreen(store: store)
                : SplashGate(
                    // The Editor's splash plays each time a home screen starts
                    // (App opened, or another profile chosen).
                    key: ValueKey('splash-${store.configVersion}'),
                    doc: store.config!,
                    child: HomeScreen(
                      // A new configuration starts a fresh home screen.
                      key: ValueKey('config-${store.configVersion}'),
                      store: store,
                    ),
                  ),
          ),
        );
      },
    );
  }
}
