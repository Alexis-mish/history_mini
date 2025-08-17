import 'package:flutter/material.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  final apiKey = dotenv.env['API_KEY'];

  if (apiKey == null) {
    print('Error: API_KEY not found in .env file');
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text("Error: API_KEY not found in .env file")))));
    return;
  }
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    print('Error al inicializar Firebase: $e');
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text("Error: Firebase no inicializado. Asegúrate de que flutterfire configure se ejecutó correctamente y que los archivos de configuración están en su lugar.")))));
    return;
  }


  Gemini.init(apiKey: apiKey);

  runApp(const MyApp());
}


class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'History Mini',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.grey[900],
        cardColor: Colors.grey[800],
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white),
          headlineSmall: TextStyle(color: Colors.white),
          labelLarge: TextStyle(color: Colors.white),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white70),
          ),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white70),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blueAccent),
          ),
          labelStyle: const TextStyle(color: Colors.white70),
          hintStyle: const TextStyle(color: Colors.white70),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(foregroundColor: Colors.white),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black87,
        ),
        dropdownMenuTheme: DropdownMenuThemeData(
          menuStyle: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(Colors.grey[800]),
          ),
        ),
      ),
      themeMode: ThemeMode.dark,
      // Utiliza StreamBuilder para reaccionar a los cambios de autenticación.
      home: StreamBuilder<User?>(
        stream: _auth.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Muestra un indicador de carga mientras se verifica el estado.
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          if (snapshot.hasData) {
            return const MyHomePage();
          } else {
            
            return const LoginScreen();
          }
        },
      ),
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  Future<void> _handleGoogleSignIn(BuildContext context) async {
    try {
      final googleClientId = dotenv.env['GOOGLE_CLIENT_ID'];
      if (googleClientId == null) {
        throw Exception('GOOGLE_CLIENT_ID not found in .env file.');
      }

      final GoogleSignInAccount? googleUser = await GoogleSignIn(
        clientId: googleClientId,
      ).signIn();
      
      final GoogleSignInAuthentication? googleAuth = await googleUser?.authentication;

      if (googleAuth == null) {
        return;
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al iniciar sesión con Google: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Iniciar Sesión'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => _handleGoogleSignIn(context),
                icon: const Icon(Icons.login),
                label: const Text('Iniciar Sesión con Google'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _animalController = TextEditingController();
  String _historiaGenerada = '';
  final gemini = Gemini.instance;
  String? _tipoDeCuentoSeleccionado;
  final List<String> _tiposDeCuento = ['Aventura', 'Terror', 'Romance', 'Fantasía', 'Ciencia Ficción', 'Misterio', 'Humor'];
  final FlutterTts flutterTts = FlutterTts();
  late TabController _tabController;
  List<Map<String, String>> _cuentosFavoritos = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cargarCuentosGuardados();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _speak() async {
    await flutterTts.setLanguage("es-ES");
    await flutterTts.setVoice({
      "name": "es-MX-female-1",
      "locale": "es-ES",
    });
    await flutterTts.setSpeechRate(1.4);
    await flutterTts.speak(_historiaGenerada);
  }

  Future<void> _guardarCuento() async {
    print('Intentando guardar cuento...');
    if (_historiaGenerada.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      List<String>? savedStoriesJson = prefs.getStringList('cuentosGuardados');
      List<Map<String, String>> savedStories = (savedStoriesJson ?? [])
          .map((json) => jsonDecode(json) as Map<String, String>)
          .toList();

      final cuentoAGuardar = {
        'titulo': 'Cuento de ${_nombreController.text}',
        'contenido': _historiaGenerada,
        'nombreNino': _nombreController.text,
        'animalFavorito': _animalController.text,
        'tipoDeCuento': _tipoDeCuentoSeleccionado ?? '',
        'fechaGuardado': DateTime.now().toIso8601String(),
      };

      savedStories.add(cuentoAGuardar);

      final updatedSavedStoriesJson = savedStories
          .map((story) => jsonEncode(story))
          .toList();
      await prefs.setStringList('cuentosGuardados', updatedSavedStoriesJson);
      await _cargarCuentosGuardados();
      print('Cuento guardado.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cuento guardado en favoritos')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay cuento generado para guardar')),
        );
      }
    }
  }

  Future<void> _cargarCuentosGuardados() async {
    print('Intentando cargar cuentos guardados...');
    final prefs = await SharedPreferences.getInstance();
    List<String>? savedStoriesJson = prefs.getStringList('cuentosGuardados');
    print('Reading from SharedPreferences: $savedStoriesJson');
    if (savedStoriesJson == null || savedStoriesJson.isEmpty) {
      print('No saved stories found.');
      setState(() {
        _cuentosFavoritos = [];
      });
      return;
    }
    try {
      final cuentos = savedStoriesJson
          .map((json) => Map<String, String>.from(jsonDecode(json)))
          .toList();
      print('Saved stories loaded: $cuentos');
      setState(() {
        _cuentosFavoritos = cuentos;
      });
    } catch (e) {
      print('Error al cargar cuentos guardados: $e');
      setState(() {
        _cuentosFavoritos = [];
      });
    }
  }

  void _generarHistoria() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _historiaGenerada = '';
      });

      final nombre = _nombreController.text;
      final animal = _animalController.text;
      final tipoDeCuento = _tipoDeCuentoSeleccionado != null && _tipoDeCuentoSeleccionado!.isNotEmpty
          ? 'de tipo $_tipoDeCuentoSeleccionado'
          : '';

      final prompt =
          'Escribe una historia (sin restricciones) donde el personaje principal se llama $nombre y algo que le gusta es $animal. La historia debe ser alegre y tener una moraleja sencilla, y que sea $tipoDeCuento.';

      try {
        final response = await gemini.prompt(parts: [Part.text(prompt)]);
        if (mounted) {
          setState(() {
            _historiaGenerada = response!.output!;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _historiaGenerada = 'Error al generar la historia: $e';
          });
        }
        print('Error al generar la historia: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }


  void _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      await GoogleSignIn().signOut();
    } catch (e) {
      print('Error al cerrar sesión: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History Mini'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Cerrar Sesión',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Generar Cuento'),
            Tab(text: 'Favoritos'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                children: <Widget>[
                  TextFormField(
                    controller: _nombreController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor, introduce el nombre.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _animalController,
                    decoration: const InputDecoration(
                      labelText: 'Algo Favorito',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor, introduce algo que te guste.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Cuento (Opcional)',
                      border: OutlineInputBorder(),
                    ),
                    value: _tipoDeCuentoSeleccionado,
                    items: _tiposDeCuento.map((String tipo) {
                      return DropdownMenuItem<String>(
                        value: tipo,
                        child: Text(tipo),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _tipoDeCuentoSeleccionado = newValue;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _generarHistoria,
                    child: const Text('Generar Historia'),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          if (_isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 32.0),
                              child: CircularProgressIndicator(),
                            )
                          else ...[
                            Text(_historiaGenerada),
                            if (_historiaGenerada.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 16.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: _speak,
                                      icon: const Icon(Icons.record_voice_over),
                                      label: const Text('Escuchar'),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: _guardarCuento,
                                      icon: const Icon(Icons.save_alt),
                                      label: const Text('Guardar'),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () async {
                      var voices = await flutterTts.getVoices;
                      print("Voces disponibles: $voices");
                    },
                    child: const Text('Mostrar Voces'),
                  ),
                ],
              ),
            ),
          ),
          ListView.builder(
            itemCount: _cuentosFavoritos.length,
            itemBuilder: (context, index) {
              final cuento = _cuentosFavoritos[index];
              return Card(
                margin: const EdgeInsets.all(8.0),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cuento['titulo'] ?? 'Sin título',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        cuento['contenido'] ?? '',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
