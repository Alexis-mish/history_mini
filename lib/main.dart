import 'package:flutter/material.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

Future<void> main() async { 
  WidgetsFlutterBinding.ensureInitialized(); 
  
  await dotenv.load(fileName: ".env"); 

  final apiKey = dotenv.env['API_KEY']; 

  if (apiKey == null) {
    print('Error: GEMINI_API_KEY no encontrada en el archivo .env');
    return;
  }
  
  Gemini.init(apiKey: apiKey); // <-- 6. Usa la API key
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
            borderSide: BorderSide(color: Colors.white70), // Color del borde
          ),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white70), // Color del borde habilitado
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blueAccent), // Color del borde al enfocar
          ),
          labelStyle: const TextStyle(color: Colors.white70), // Color del texto de la etiqueta
          hintStyle: const TextStyle(color: Colors.white70), // Color del texto de la sugerencia
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
      themeMode: ThemeMode.dark, // Enable dark mode
      home: const MyHomePage(),
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
  bool _isLoading = false; //importante!!!!! este es el estado de la animacion de carga

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cargarCuentosGuardados(); // Cargar los cuentos al inicializar la pantalla
  }

  Future<void> _speak() async {
    await flutterTts.setLanguage("es-ES"); // cambiar el idioma
    await flutterTts.setVoice({"name": "es-MX-female-1", "locale": "es-ES"}); // Aca se cambia la voz
    await flutterTts.setSpeechRate(1.4); // Ajustar la velocidad
    await flutterTts.speak(_historiaGenerada);
  }

  Future<void> _guardarCuento() async {
    print('Intentando guardar cuento...');
    if (_historiaGenerada.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      List<String>? savedStoriesJson = prefs.getStringList('cuentosGuardados');
      List<Map<String, String>> savedStories = savedStoriesJson?.map((json) => jsonDecode(json) as Map<String, String>).toList() ?? [];

      final cuentoAGuardar = {
        'titulo': 'Cuento de ${_nombreController.text}',
        'contenido': _historiaGenerada,
        'nombreNino': _nombreController.text,
        'animalFavorito': _animalController.text,
        'tipoDeCuento': _tipoDeCuentoSeleccionado ?? '',
        'fechaGuardado': DateTime.now().toIso8601String(),
      };

      savedStories.add(cuentoAGuardar);

      final updatedSavedStoriesJson = savedStories.map((story) => jsonEncode(story)).toList();
      await prefs.setStringList('cuentosGuardados', updatedSavedStoriesJson);
      print('Cuento guardado.'); // <--- Agregar este print
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
    print('Intentando cargar cuentos guardados...'); // <--- Agregar este print
    final prefs = await SharedPreferences.getInstance();
    List<String>? savedStoriesJson = prefs.getStringList('cuentosGuardados');
    if (savedStoriesJson != null) {
      setState(() {
        _cuentosFavoritos = savedStoriesJson
            .map((json) => jsonDecode(json) as Map<String, String>)
            .toList();
      });
      print('Cuentos guardados cargados: $_cuentosFavoritos'); // <--- Agregar este print
    } else {
      setState(() {
        _cuentosFavoritos = [];
      });
      print('No se encontraron cuentos guardados.'); // <--- Agregar este print
    }
  }

  void _generarHistoria() async {
  if (_formKey.currentState!.validate()) {
    setState(() {
      _isLoading = true; // Inicia la animación de carga
      _historiaGenerada = ''; // Limpia la historia anterior
    });

    final nombre = _nombreController.text;
    final animal = _animalController.text;
    final tipoDeCuento = _tipoDeCuentoSeleccionado != null ? 'de tipo $_tipoDeCuentoSeleccionado' : '';

    final prompt = 'Escribe una historia (sin restricciones) donde el personaje principal se llama $nombre y algo que le gusta es $animal. La historia debe ser alegre y tener una moraleja sencilla, y que sea $tipoDeCuento.';

    try {
      final response = await gemini.prompt(
        parts: [Part.text(prompt)],
      );
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
          _isLoading = false; // Detiene la animación de carga
        });
      }
    }
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History Mini'),
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
          // Tab for generating stories
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
                        ]
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton( // Botón temporal para mostrar las voces
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
          // Tab for favorite stories
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