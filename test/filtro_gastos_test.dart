import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:exploraec/controllers/auth_controller.dart';
import 'package:exploraec/controllers/gastos_controller.dart';
import 'package:exploraec/i18n/app_translations.dart';
import 'package:exploraec/screens/gastos_screen.dart';
import 'package:exploraec/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Servidor falso en memoria para la prueba de widget de filtro de gastos.
class _Servidor implements HttpClientAdapter {
  final gastos = <Map<String, dynamic>>[];

  ResponseBody _json(Object? cuerpo, int codigo, [Map<String, List<String>> h = const {}]) =>
      ResponseBody.fromString(
        cuerpo == null ? '' : jsonEncode(cuerpo),
        codigo,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          ...h,
        },
      );

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? cuerpo, Future<void>? cancelar) async {
    final ruta = o.path;
    if (ruta == '/usuarios/token') {
      return _json({'access_token': 'tok-prueba', 'token_type': 'bearer'}, 200);
    }
    if (ruta == '/usuarios/me') {
      return _json({'id': 1, 'email': 'prueba@exploraec.com'}, 200);
    }
    if (ruta == '/gastos/categorias') {
      return _json(
        {'categorias': ['comida', 'transporte', 'entretenimiento', 'otros'], 'limite_por_categoria': 500.0},
        200,
      );
    }
    if (ruta == '/gastos/' && o.method == 'GET') {
      return _json(gastos, 200, {'x-total-count': ['${gastos.length}']});
    }
    return _json({'detail': 'ruta no prevista: $ruta'}, 404);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() => Hive.init(Directory.systemTemp.createTempSync('hive_filtro').path));

  tearDown(() async {
    Get.reset();
  });

  Future<GastosController> prepararEntorno(WidgetTester tester) async {
    Get.reset();
    Get.testMode = true;
    await Hive.deleteFromDisk();
    FlutterSecureStorage.setMockInitialValues({'access_token': 'tok-prueba'});

    final servidor = _Servidor();
    servidor.gastos.addAll([
      {
        'id': 1,
        'descripcion': 'Almuerzo en el Mercado Central',
        'monto': 6.50,
        'categoria': 'comida',
        'fecha': '2026-10-10',
      },
      {
        'id': 2,
        'descripcion': 'Boleto de autobús urbano',
        'monto': 0.35,
        'categoria': 'transporte',
        'fecha': '2026-10-10',
      },
      {
        'id': 3,
        'descripcion': 'Cena tradicional',
        'monto': 5.00,
        'categoria': 'comida',
        'fecha': '2026-10-11',
      },
    ]);

    Get.put(ApiClient(dio: Dio(BaseOptions(baseUrl: 'http://prueba'))..httpClientAdapter = servidor));
   late AuthController auth;
late GastosController controller;

await tester.runAsync(() async {
  auth = Get.put(AuthController());

  for (var i = 0; i < 200 && auth.restaurando.value; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  controller = Get.put(GastosController());

  for (var i = 0; i < 200 && controller.gastos.isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  for (var i = 0;
      i < 200 && controller.estado.value.name != 'exito';
      i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
});

expect(auth.restaurando.value, isFalse);
expect(controller.gastos, isNotEmpty);
expect(controller.estado.value.name, 'exito');

return controller;
  }

  testWidgets('Al elegir «comida», solo se ven los gastos de comida', (tester) async {
    await prepararEntorno(tester);

    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: const Locale('es', 'EC'),
        home: const GastosScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Al inicio deben verse los gastos de ambas categorías
    expect(find.text('Almuerzo en el Mercado Central'), findsOneWidget);
    expect(find.text('Boleto de autobús urbano'), findsOneWidget);
    expect(find.text('Cena tradicional'), findsOneWidget);

    // Los chips deben incluir «Todas», «comida» y «transporte», pero no «entretenimiento» ni «otros»
    expect(find.widgetWithText(ChoiceChip, 'Todas'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'comida'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'transporte'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'entretenimiento'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'otros'), findsNothing);

    // Al tocar el chip «comida»
    await tester.tap(find.widgetWithText(ChoiceChip, 'comida'));
    await tester.pumpAndSettle();

    // Solo se ven los gastos de comida; el de transporte desaparece
    expect(find.text('Almuerzo en el Mercado Central'), findsOneWidget);
    expect(find.text('Cena tradicional'), findsOneWidget);
    expect(find.text('Boleto de autobús urbano'), findsNothing);

    // Al tocar «Todas», se vuelven a mostrar todos los gastos
    await tester.tap(find.widgetWithText(ChoiceChip, 'Todas'));
    await tester.pumpAndSettle();

    expect(find.text('Almuerzo en el Mercado Central'), findsOneWidget);
    expect(find.text('Boleto de autobús urbano'), findsOneWidget);
    expect(find.text('Cena tradicional'), findsOneWidget);
  });
}
